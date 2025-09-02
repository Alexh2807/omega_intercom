// lib/intercom_service.dart
// Audio intercom over UDP with optional EQ (high-pass/low-pass) and noise gate.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ConnectionMode { lan, internet }

class PeerInfo {
  final String id;
  final String name;
  final InternetAddress address;
  final int port;
  final bool isServer;
  final int? color; // ARGB 0xAARRGGBB
  const PeerInfo({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    this.isServer = false,
    this.color,
  });
}

// Android native audio player via MethodChannel
class _NativePlayer {
  static const MethodChannel _ch = MethodChannel('intercom_native_audio');

  Future<void> start({int sampleRate = 16000}) async {
    try {
      await _ch.invokeMethod('start', {'sr': sampleRate});
    } catch (e) {
      debugPrint('Native start error: $e');
    }
  }

  Future<void> write(Uint8List data) async {
    try {
      await _ch.invokeMethod('write', data);
    } catch (e) {
      debugPrint('Native write error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _ch.invokeMethod('stop');
    } catch (e) {
      debugPrint('Native stop error: $e');
    }
  }
}

class IntercomService {
  // PCM16 mono @ 16 kHz
  static const int _sampleRate = 16000;

  // Ports
  static const int _lanAudioPort = 50005; // audio PCM LAN
  static const int _lanDiscoveryPort = 50004; // LAN discovery
  static const int _defaultInternetPort = 55667;

  // Network / audio
  RawDatagramSocket? _audioSock;
  RawDatagramSocket? _discoverySock;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;

  final _native = _NativePlayer();

  bool _initialized = false;

  // Mode
  ConnectionMode _mode = ConnectionMode.lan;

  // Internet
  String? _serverHost;
  int _serverPort = _defaultInternetPort;
  InternetAddress? _serverAddress;

  // Identity / prefs
  String _selfId =
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${Random().nextInt(0xFFFF).toRadixString(16)}';
  String _displayName = 'Appareil';
  int _avatarColor = 0xFF3F51B5; // ARGB
  double _masterGain = 1.0; // playback
  double _micGain = 1.0; // capture
  bool _isTalking = false; // PTT state
  double _duckFactor = 0.15; // playback attenuation while talking
  int _gateLevel = 180; // simple gate threshold (avg |amplitude|)
  SharedPreferences? _prefs;
  bool _prefsLoaded = false;

  // Simple EQ: cut lows/highs (0 = disabled)
  int _micLowCutHz = 0;
  int _micHighCutHz = 0;
  int _playLowCutHz = 0;
  int _playHighCutHz = 0;
  _Biquad? _fMicHP;
  _Biquad? _fMicLP;
  _Biquad? _fPlayHP;
  _Biquad? _fPlayLP;

  // Roster
  final Map<String, PeerInfo> _netPeers = {}; // Internet: id -> PeerInfo
  final Map<String, PeerInfo> _lanPeers = {}; // LAN: ip -> PeerInfo
  final Map<String, DateTime> _lanLastSeen = {};
  int _internetPeerCount = 0;

  // Periodic
  Timer? _helloTimer;
  Timer? _presenceTimer;

  // Per-peer audio settings
  final Set<String> _muted = <String>{};
  final Map<String, double> _gain = <String, double>{};

  // UI streams
  final _logC = StreamController<String>.broadcast();
  final _peersC = StreamController<List<PeerInfo>>.broadcast();
  Stream<String> get logStream => _logC.stream;
  Stream<List<PeerInfo>> get peersStream => _peersC.stream;
  void _log(String m) {
    if (kDebugMode) print('[Intercom] $m');
    _logC.add(m);
  }

  // ===== Prefs / identity =====
  Future<void> _ensurePrefs() async {
    if (_prefsLoaded) return;
    _prefs = await SharedPreferences.getInstance();
    final savedId = _prefs!.getString('user_id');
    if (savedId != null && savedId.isNotEmpty) {
      _selfId = savedId;
    } else {
      _prefs!.setString('user_id', _selfId);
    }
    final dn = _prefs!.getString('display_name');
    if (dn != null && dn.isNotEmpty) _displayName = dn;
    _avatarColor = _prefs!.getInt('avatar_color') ?? _avatarColor;
    _masterGain = _prefs!.getDouble('master_gain') ?? _masterGain;
    _micGain = _prefs!.getDouble('mic_gain') ?? _micGain;
    _duckFactor = _prefs!.getDouble('duck_factor') ?? _duckFactor;
    _gateLevel = _prefs!.getInt('gate_level') ?? _gateLevel;
    _micLowCutHz = _prefs!.getInt('mic_low_cut_hz') ?? _micLowCutHz;
    _micHighCutHz = _prefs!.getInt('mic_high_cut_hz') ?? _micHighCutHz;
    _playLowCutHz = _prefs!.getInt('play_low_cut_hz') ?? _playLowCutHz;
    _playHighCutHz = _prefs!.getInt('play_high_cut_hz') ?? _playHighCutHz;
    _rebuildFilters();
    _prefsLoaded = true;
  }

  String get displayName => _displayName;
  int get avatarColor => _avatarColor;
  double get masterGain => _masterGain;
  double get micGain => _micGain;
  String get selfId => _selfId;
  double get duckFactor => _duckFactor;
  int get gateLevel => _gateLevel;
  int get micLowCutHz => _micLowCutHz;
  int get micHighCutHz => _micHighCutHz;
  int get playbackLowCutHz => _playLowCutHz;
  int get playbackHighCutHz => _playHighCutHz;

  Future<void> setDisplayName(String name) async {
    await _ensurePrefs();
    _displayName = name.trim().isEmpty ? 'Utilisateur' : name.trim();
    await _prefs!.setString('display_name', _displayName);
    _sendHello();
    _sendPresence();
  }

  Future<void> setAvatarColor(int argb) async {
    await _ensurePrefs();
    _avatarColor = argb;
    await _prefs!.setInt('avatar_color', _avatarColor);
    _sendHello();
    _sendPresence();
  }

  Future<void> setMasterGain(double g) async {
    await _ensurePrefs();
    _masterGain = g.clamp(0.0, 2.0);
    await _prefs!.setDouble('master_gain', _masterGain);
  }

  Future<void> setMicGain(double g) async {
    await _ensurePrefs();
    _micGain = g.clamp(0.0, 2.0);
    await _prefs!.setDouble('mic_gain', _micGain);
  }

  Future<void> setDuckFactor(double f) async {
    await _ensurePrefs();
    _duckFactor = f.clamp(0.0, 1.0);
    await _prefs!.setDouble('duck_factor', _duckFactor);
  }

  Future<void> setGateLevel(int level) async {
    await _ensurePrefs();
    _gateLevel = level.clamp(0, 2000);
    await _prefs!.setInt('gate_level', _gateLevel);
  }

  Future<void> setMicLowCutHz(int hz) async {
    await _ensurePrefs();
    _micLowCutHz = hz.clamp(0, _sampleRate ~/ 2 - 1);
    await _prefs!.setInt('mic_low_cut_hz', _micLowCutHz);
    _rebuildFilters();
  }

  Future<void> setMicHighCutHz(int hz) async {
    await _ensurePrefs();
    _micHighCutHz = hz.clamp(0, _sampleRate ~/ 2 - 1);
    await _prefs!.setInt('mic_high_cut_hz', _micHighCutHz);
    _rebuildFilters();
  }

  Future<void> setPlaybackLowCutHz(int hz) async {
    await _ensurePrefs();
    _playLowCutHz = hz.clamp(0, _sampleRate ~/ 2 - 1);
    await _prefs!.setInt('play_low_cut_hz', _playLowCutHz);
    _rebuildFilters();
  }

  Future<void> setPlaybackHighCutHz(int hz) async {
    await _ensurePrefs();
    _playHighCutHz = hz.clamp(0, _sampleRate ~/ 2 - 1);
    await _prefs!.setInt('play_high_cut_hz', _playHighCutHz);
    _rebuildFilters();
  }

  Future<void> resetSettings() async {
    await _ensurePrefs();
    try {
      final keys = _prefs!.getKeys();
      for (final k in keys) {
        if (k == 'display_name' ||
            k == 'avatar_color' ||
            k == 'master_gain' ||
            k == 'mic_gain' ||
            k == 'duck_factor' ||
            k == 'gate_level' ||
            k == 'mic_low_cut_hz' ||
            k == 'mic_high_cut_hz' ||
            k == 'play_low_cut_hz' ||
            k == 'play_high_cut_hz') {
          await _prefs!.remove(k);
        }
        if (k.startsWith('peer_gain_') || k.startsWith('peer_mute_')) {
          await _prefs!.remove(k);
        }
      }
    } catch (_) {}
    _displayName = 'Appareil';
    _avatarColor = 0xFF3F51B5;
    _masterGain = 1.0;
    _micGain = 1.0;
    _muted.clear();
    _gain.clear();
    _duckFactor = 0.15;
    _gateLevel = 180;
    _micLowCutHz = 0;
    _micHighCutHz = 0;
    _playLowCutHz = 0;
    _playHighCutHz = 0;
    _rebuildFilters();
    _emitPeers();
    _sendHello();
    _sendPresence();
  }

  void setMuted(String peerId, bool m) {
    if (m) {
      _muted.add(peerId);
    } else {
      _muted.remove(peerId);
    }
    try {
      _prefs?.setBool('peer_mute_$peerId', _muted.contains(peerId));
    } catch (_) {}
  }

  void setGain(String peerId, double g) {
    _gain[peerId] = g.clamp(0.0, 2.0);
    try {
      _prefs?.setDouble('peer_gain_$peerId', _gain[peerId]!);
    } catch (_) {}
  }

  bool isMuted(String peerId) => _muted.contains(peerId);
  double gainOf(String peerId) => _gain[peerId] ?? 1.0;

  // ===== API (UI) =====
  Future<bool> requestPermissions() async {
    final mic = await Permission.microphone.request();
    final ok = mic.isGranted;
    if (!ok) _log('Permission micro refusée');
    return ok;
  }

  void setMode(ConnectionMode mode) {
    _mode = mode;
    _log('Mode sélectionné: ${_mode.name}');
    _emitPeers();
  }

  void setInternetEndpoint({required String host, int? port}) {
    _serverHost = host.trim();
    if (port != null) _serverPort = port;
    _serverAddress = null;
    _log('Endpoint Internet: $_serverHost:$_serverPort');
    _emitPeers();
  }

  void setPeer(String ip) {
    final addr = InternetAddress(ip.trim());
    _lanPeers[addr.address] = PeerInfo(
      id: 'manual',
      name: 'Appareil',
      address: addr,
      port: _lanAudioPort,
      isServer: false,
    );
    _lanLastSeen[addr.address] = DateTime.now();
    _emitPeers();
  }

  Future<void> start() async {
    await _ensurePrefs();
    if (_initialized) {
      _log('Déjà initialisé');
      return;
    }

    // Audio UDP (rx)
    _audioSock = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _lanAudioPort,
      reuseAddress: true,
      reusePort: true,
    );
    _audioSock!.readEventsEnabled = true;
    _audioSock!.listen(_onAudioUdp);
    _log('Audio UDP: écoute sur 0.0.0.0:$_lanAudioPort');

    // Start native player
    await _native.start(sampleRate: _sampleRate);

    // LAN discovery
    _discoverySock = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _lanDiscoveryPort,
      reuseAddress: true,
      reusePort: true,
    );
    _discoverySock!.broadcastEnabled = true;
    _discoverySock!.readEventsEnabled = true;
    _discoverySock!.listen(_onDiscoveryUdp);
    _log('Découverte UDP: écoute sur 0.0.0.0:$_lanDiscoveryPort');

    // Pings + purge
    _helloTimer?.cancel();
    _helloTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _sendHello();
      _purgeOldPeers();
    });
    _sendHello();

    // Internet presence
    if (_mode == ConnectionMode.internet) {
      _presenceTimer?.cancel();
      _presenceTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _sendPresence());
      _sendPresence();
    }

    _initialized = true;
  }

  Future<void> startTalking() async {
    if (!await requestPermissions()) {
      throw Exception('Permission micro refusée');
    }
    if (!_initialized) await start();

    if (_mode == ConnectionMode.internet) {
      await _resolveServerIfNeeded();
      if (_serverAddress == null) {
        _log('Impossible de résoudre $_serverHost');
        throw Exception('Serveur non résolu');
      }
    }

    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );
    _micSub?.cancel();
    _micSub = stream.listen((Uint8List chunk) {
      try {
        if (chunk.isEmpty) return;
        if (!_passesNoiseGate(chunk)) return;
        // EQ mic
        Uint8List proc = chunk;
        if (_fMicHP != null || _fMicLP != null) {
          proc = _applyEqPcm16(Uint8List.fromList(proc), _fMicHP, _fMicLP);
        }
        // Prepare packet: 'IC' + 0x01 + idLen + selfId + PCM16
        final idBytes = utf8.encode(_selfId);
        final headerLen = 4 + idBytes.length;
        // Mic gain
        Uint8List micPcm = proc;
        if (_micGain != 1.0) {
          micPcm = _applyGainPcm16(Uint8List.fromList(micPcm), _micGain);
        }
        final data = Uint8List(headerLen + micPcm.length);
        final b = data.buffer.asUint8List();
        b[0] = 0x49; // 'I'
        b[1] = 0x43; // 'C'
        b[2] = 0x01; // version
        b[3] = idBytes.length & 0xFF;
        b.setRange(4, 4 + idBytes.length, idBytes);
        b.setRange(4 + idBytes.length, data.length, micPcm);

        if (_mode == ConnectionMode.lan) {
          for (final p in _lanPeers.values) {
            _audioSock?.send(data, p.address, p.port);
          }
        } else {
          final dst = _serverAddress;
          if (dst != null) _audioSock?.send(data, dst, _serverPort);
        }
      } catch (e) {
        _log('Erreur envoi UDP: $e');
      }
    });
    _isTalking = true;
    _log('Capture micro démarrée');
  }

  Future<void> stopTalking() async {
    await _micSub?.cancel();
    _micSub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    _isTalking = false;
    _log('Capture micro arrêtée');
  }

  Future<void> stop() async {
    await stopTalking();
    _helloTimer?.cancel();
    _helloTimer = null;
    _discoverySock?.close();
    _discoverySock = null;
    await _native.stop();
    _audioSock?.close();
    _audioSock = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _initialized = false;
    _lanPeers.clear();
    _lanLastSeen.clear();
    _netPeers.clear();
    _emitPeers();
    _log('Intercom arrêté');
  }

  void dispose() {
    _logC.close();
    _peersC.close();
  }

  // ===== Presence (internet) =====
  void _sendPresence() {
    if (_mode != ConnectionMode.internet) return;
    final dst = _serverAddress;
    if (dst == null) return;
    final msg = 'ICSV1|PRES|$_selfId|$_displayName|$_avatarColor';
    _audioSock?.send(utf8.encode(msg), dst, _serverPort);
  }

  // ===== DSP utils =====
  Uint8List _applyGainPcm16(Uint8List pcm, double gain) {
    try {
      final bd = ByteData.view(pcm.buffer, 0, pcm.lengthInBytes);
      for (int i = 0; i < pcm.lengthInBytes; i += 2) {
        int s = bd.getInt16(i, Endian.little);
        double v = s * gain;
        if (v > 32767) v = 32767;
        if (v < -32768) v = -32768;
        bd.setInt16(i, v.toInt(), Endian.little);
      }
      return pcm;
    } catch (_) {
      return pcm;
    }
  }

  Uint8List _applyEqPcm16(Uint8List pcm, _Biquad? hp, _Biquad? lp) {
    try {
      final bd = ByteData.view(pcm.buffer, 0, pcm.lengthInBytes);
      for (int i = 0; i < pcm.lengthInBytes; i += 2) {
        int s = bd.getInt16(i, Endian.little);
        double v = s.toDouble();
        if (hp != null) v = hp.process(v);
        if (lp != null) v = lp.process(v);
        if (v > 32767) v = 32767;
        if (v < -32768) v = -32768;
        bd.setInt16(i, v.toInt(), Endian.little);
      }
      return pcm;
    } catch (_) {
      return pcm;
    }
  }

  // Simple noise gate (avg |amplitude|)
  bool _passesNoiseGate(Uint8List pcm) {
    try {
      if (pcm.lengthInBytes < 2) return false;
      final bd = ByteData.view(pcm.buffer, 0, pcm.lengthInBytes);
      int count = 0;
      int sum = 0;
      for (int i = 0; i < pcm.lengthInBytes; i += 2) {
        int s = bd.getInt16(i, Endian.little);
        if (s < 0) s = -s;
        sum += s;
        count++;
      }
      if (count == 0) return false;
      final avg = sum / count;
      return avg > _gateLevel;
    } catch (_) {
      return true;
    }
  }

  // ===== UDP: audio reception =====
  DateTime _lastRxLog = DateTime.fromMillisecondsSinceEpoch(0);
  void _onAudioUdp(RawSocketEvent ev) {
    if (ev != RawSocketEvent.read) return;
    final dg = _audioSock?.receive();
    if (dg == null) return;
    final bytes = dg.data;

    // Control messages (PEERS / PRES / GONE)
    try {
      if (bytes.length >= 6 && bytes[0] == 0x49 && bytes[1] == 0x43) {
        final txt = utf8.decode(bytes, allowMalformed: true);
        if (txt.startsWith('ICSV1|PEERS|')) {
          final parts = txt.split('|');
          final n = int.tryParse(parts[2]) ?? 0;
          if (n != _internetPeerCount) {
            _internetPeerCount = n;
            _emitPeers();
          }
          return;
        }
        if (txt.startsWith('ICSV1|PRES|')) {
          final parts = txt.split('|');
          if (parts.length >= 4) {
            final id = parts[2];
            final name = parts[3];
            int? color;
            if (parts.length >= 5) {
              try {
                color = int.parse(parts[4]);
              } catch (_) {
                color = null;
              }
            }
            if (id != _selfId) {
              _netPeers[id] = PeerInfo(
                id: id,
                name: name.isEmpty ? 'Utilisateur' : name,
                address: _serverAddress ?? InternetAddress.anyIPv4,
                port: _serverPort,
                isServer: false,
                color: color,
              );
              try {
                final mg = _prefs?.getDouble('peer_gain_$id');
                if (mg != null) _gain[id] = mg;
                final mm = _prefs?.getBool('peer_mute_$id');
                if (mm == true) {
                  _muted.add(id);
                } else if (mm == false) {
                  _muted.remove(id);
                }
              } catch (_) {}
              _emitPeers();
            }
          }
          return;
        }
        if (txt.startsWith('ICSV1|GONE|')) {
          final parts = txt.split('|');
          if (parts.length >= 3) {
            _netPeers.remove(parts[2]);
            _emitPeers();
          }
          return;
        }
      }
    } catch (_) {}

    // Audio packet: IC|01|idLen|id|pcm16
    Uint8List payload;
    try {
      if (bytes.length >= 4 && bytes[0] == 0x49 && bytes[1] == 0x43 && bytes[2] == 0x01) {
        final idLen = bytes[3] & 0xFF;
        if (bytes.length >= 4 + idLen) {
          final senderId = utf8.decode(bytes.sublist(4, 4 + idLen));
          if (senderId == _selfId) return; // mix-minus
          payload = bytes.sublist(4 + idLen);
        } else {
          payload = bytes;
        }
      } else {
        payload = bytes;
      }
    } catch (_) {
      payload = bytes;
    }

    if (payload.isNotEmpty) {
      Uint8List toPlay = payload;
      try {
        if (bytes.length >= 4 && bytes[0] == 0x49 && bytes[1] == 0x43 && bytes[2] == 0x01) {
          final idLen = bytes[3] & 0xFF;
          if (bytes.length >= 4 + idLen) {
            final sid = utf8.decode(bytes.sublist(4, 4 + idLen), allowMalformed: true);
            if (_muted.contains(sid)) return;
            final g = _gain[sid] ?? 1.0;
            if (g != 1.0) {
              toPlay = _applyGainPcm16(Uint8List.fromList(toPlay), g);
            }
          }
        }
      } catch (_) {}
      // Playback EQ
      if (_fPlayHP != null || _fPlayLP != null) {
        toPlay = _applyEqPcm16(Uint8List.fromList(toPlay), _fPlayHP, _fPlayLP);
      }
      final double globalGain = _masterGain * (_isTalking ? _duckFactor : 1.0);
      if (globalGain != 1.0) {
        toPlay = _applyGainPcm16(Uint8List.fromList(toPlay), globalGain);
      }
      _native.write(toPlay);
    }

    final now = DateTime.now();
    if (now.difference(_lastRxLog).inMilliseconds > 500) {
      _lastRxLog = now;
      _log('RX ${dg.data.length} bytes de ${dg.address.address}:${dg.port}');
    }

    if (_mode == ConnectionMode.lan) {
      final ip = dg.address.address;
      if (!_lanPeers.containsKey(ip)) {
        _lanPeers[ip] = PeerInfo(
          id: 'unknown',
          name: 'Appareil',
          address: dg.address,
          port: dg.port,
          isServer: false,
        );
        _emitPeers();
      }
      _lanLastSeen[ip] = DateTime.now();
    }
  }

  // ===== UDP: LAN discovery =====
  void _onDiscoveryUdp(RawSocketEvent ev) {
    if (ev != RawSocketEvent.read) return;
    final dg = _discoverySock?.receive();
    if (dg == null) return;
    try {
      final txt = utf8.decode(dg.data);
      final parts = txt.split('|');
      if (parts.length < 4) return;
      final cmd = parts[0];
      final peerId = parts[1];
      if (peerId == _selfId) return;
      final peerPort = int.tryParse(parts[2]) ?? _lanAudioPort;
      final ip = dg.address.address;
      String peerName = parts.length >= 4 ? parts[3] : 'Appareil';
      int? color;
      if (parts.length >= 5) {
        try {
          color = int.parse(parts[4]);
        } catch (_) {
          color = null;
        }
      }
      _lanPeers[ip] = PeerInfo(
        id: peerId,
        name: (peerName.isEmpty ? 'Appareil' : peerName),
        address: dg.address,
        port: peerPort,
        isServer: false,
        color: color,
      );
      _lanLastSeen[ip] = DateTime.now();
      _emitPeers();
      if (cmd == 'HELLO') {
        final reply = 'HERE|$_selfId|$_lanAudioPort|$_displayName|$_avatarColor';
        _discoverySock?.send(utf8.encode(reply), dg.address, _lanDiscoveryPort);
      }
    } catch (_) {}
  }

  void _sendHello() {
    if (_discoverySock == null) return;
    final msg = 'HELLO|$_selfId|$_lanAudioPort|$_displayName|$_avatarColor';
    final bytes = utf8.encode(msg);
    final bcast = InternetAddress('255.255.255.255');
    _discoverySock!.send(bytes, bcast, _lanDiscoveryPort);
    for (final p in _lanPeers.values) {
      _discoverySock!.send(
          utf8.encode('HERE|$_selfId|$_lanAudioPort|$_displayName|$_avatarColor'),
          p.address,
          _lanDiscoveryPort);
    }
  }

  void _purgeOldPeers() {
    final now = DateTime.now();
    final toRemove = <String>[];
    _lanLastSeen.forEach((ip, ts) {
      if (now.difference(ts) > const Duration(seconds: 6)) {
        toRemove.add(ip);
      }
    });
    for (final ip in toRemove) {
      _lanLastSeen.remove(ip);
      _lanPeers.remove(ip);
    }
    if (toRemove.isNotEmpty) _emitPeers();
  }

  // ===== Internet (DNS) =====
  Future<void> _resolveServerIfNeeded() async {
    if (_serverAddress != null || _serverHost == null || _serverHost!.isEmpty) {
      _emitPeers();
      return;
    }
    final parsed = InternetAddress.tryParse(_serverHost!);
    if (parsed != null) {
      _serverAddress = parsed;
      _emitPeers();
      return;
    }
    try {
      final list = await InternetAddress.lookup(_serverHost!);
      _serverAddress = list.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => list.first,
      );
      _emitPeers();
    } catch (_) {
      _emitPeers();
    }
  }

  void _emitPeers() {
    if (_mode == ConnectionMode.internet) {
      _peersC.add(_netPeers.values.toList(growable: false));
    } else {
      _peersC.add(_lanPeers.values.toList(growable: false));
    }
  }

  void _rebuildFilters() {
    _fMicHP = (_micLowCutHz > 0)
        ? _Biquad.highPass(_sampleRate.toDouble(), _micLowCutHz.toDouble())
        : null;
    _fMicLP = (_micHighCutHz > 0)
        ? _Biquad.lowPass(_sampleRate.toDouble(), _micHighCutHz.toDouble())
        : null;
    _fPlayHP = (_playLowCutHz > 0)
        ? _Biquad.highPass(_sampleRate.toDouble(), _playLowCutHz.toDouble())
        : null;
    _fPlayLP = (_playHighCutHz > 0)
        ? _Biquad.lowPass(_sampleRate.toDouble(), _playHighCutHz.toDouble())
        : null;
  }
}

// ===== Biquad IIR (Butterworth Q ~= 0.707) =====
class _Biquad {
  final double b0, b1, b2, a1, a2;
  double _z1 = 0.0;
  double _z2 = 0.0;
  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  static _Biquad lowPass(double fs, double fc, {double q = 1.0 / 1.41421356237}) {
    final w0 = 2 * pi * (fc / fs);
    final cw = cos(w0);
    final sw = sin(w0);
    final alpha = sw / (2 * q);
    double b0 = (1 - cw) / 2;
    double b1 = 1 - cw;
    double b2 = (1 - cw) / 2;
    double a0 = 1 + alpha;
    double a1 = -2 * cw;
    double a2 = 1 - alpha;
    return _Biquad(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  static _Biquad highPass(double fs, double fc, {double q = 1.0 / 1.41421356237}) {
    final w0 = 2 * pi * (fc / fs);
    final cw = cos(w0);
    final sw = sin(w0);
    final alpha = sw / (2 * q);
    double b0 = (1 + cw) / 2;
    double b1 = -(1 + cw);
    double b2 = (1 + cw) / 2;
    double a0 = 1 + alpha;
    double a1 = -2 * cw;
    double a2 = 1 - alpha;
    return _Biquad(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  double process(double x) {
    final y = b0 * x + _z1;
    _z1 = b1 * x - a1 * y + _z2;
    _z2 = b2 * x - a2 * y;
    return y;
  }
}


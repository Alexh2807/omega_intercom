// lib/intercom_service.dart
// Audio intercom over UDP with optional EQ (high-pass/low-pass) and noise gate.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omega_intercom/audio_processor.dart';

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
class _FgService {
  static const MethodChannel _ch = MethodChannel('intercom_fg_service');
  static Future<void> start({required String title, required String body}) async {
    try { await _ch.invokeMethod('start', { 'title': title, 'body': body }); } catch (_) {}
  }
  static Future<void> stop() async { try { await _ch.invokeMethod('stop'); } catch (_) {} }
}

class IntercomService {
  // Singleton
  static final IntercomService _instance = IntercomService._internal();
  factory IntercomService() => _instance;
  IntercomService._internal();
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
  final AudioProcessor _proc = AudioProcessor();
  // Jitter buffer toggle (runtime)
  bool _jitterEnabled = true;
  _JitterBuffer? _jb;
  int _txSeq = 0;

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
  // Gate threshold (normalized 0..1). Older versions used int 0..1000.
  double _gateNorm = 0.18;
  SharedPreferences? _prefs;
  bool _prefsLoaded = false;

  // Simple EQ: cut lows/highs (0 = disabled)
  int _micLowCutHz = 0;
  int _micHighCutHz = 0;
  int _playLowCutHz = 0;
  int _playHighCutHz = 0;
  // Mic EQ handled in AudioProcessor isolate; keep only playback EQ here
  _Biquad? _fPlayHP;
  _Biquad? _fPlayLP;

  // Echo suppression (simple sidechain): reduce mic when playback energy high
  bool _echoEnabled = false;
  double _echoStrength = 0.6; // 0..1, portion to attenuate when active
  int _echoThreshold = 600; // avg |amp| threshold to trigger
  double _rxEma = 0.0; // playback energy EMA
  static const double _rxEmaAlpha = 0.2;

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
  final _micLevelC = StreamController<double>.broadcast(); // 0..1
  final _outLevelC = StreamController<double>.broadcast(); // 0..1
  Stream<String> get logStream => _logC.stream;
  Stream<List<PeerInfo>> get peersStream => _peersC.stream;
  Stream<double> get micLevelStream => _micLevelC.stream;
  Stream<double> get outLevelStream => _outLevelC.stream;
  bool get isInitialized => _initialized;
  bool get isTalking => _isTalking;
  ConnectionMode get currentMode => _mode;
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
    final bool? duckIsAtt = _prefs!.getBool('duck_is_att');
    final double storedDuck = _prefs!.getDouble('duck_factor') ?? _duckFactor;
    if (duckIsAtt == true) {
      _duckFactor = storedDuck;
    } else {
      final converted = (1.0 - storedDuck).clamp(0.0, 1.0);
      _duckFactor = converted;
      await _prefs!.setDouble('duck_factor', _duckFactor);
      await _prefs!.setBool('duck_is_att', true);
    }
    // Gate migration: prefer gate_norm (double), else convert legacy gate_level 0..1000
    if (_prefs!.containsKey('gate_norm')) {
      _gateNorm = (_prefs!.getDouble('gate_norm') ?? _gateNorm).clamp(0.0, 1.0);
    } else {
      final oldGate = _prefs!.getInt('gate_level');
      if (oldGate != null) {
        _gateNorm = (oldGate / 1000.0).clamp(0.0, 1.0);
        await _prefs!.setDouble('gate_norm', _gateNorm);
      }
    }
    _micLowCutHz = _prefs!.getInt('mic_low_cut_hz') ?? _micLowCutHz;
    _micHighCutHz = _prefs!.getInt('mic_high_cut_hz') ?? _micHighCutHz;
    _playLowCutHz = _prefs!.getInt('play_low_cut_hz') ?? _playLowCutHz;
    _playHighCutHz = _prefs!.getInt('play_high_cut_hz') ?? _playHighCutHz;
    _echoEnabled = _prefs!.getBool('echo_enabled') ?? _echoEnabled;
    _echoStrength = _prefs!.getDouble('echo_strength') ?? _echoStrength;
    _echoThreshold = _prefs!.getInt('echo_threshold') ?? _echoThreshold;
    _jitterEnabled = _prefs!.getBool('jitter_enabled') ?? _jitterEnabled;
    _autoFullDuplex = _prefs!.getBool('auto_full_duplex') ?? _autoFullDuplex;
    _rebuildFilters();
    _prefsLoaded = true;
  }

  String get displayName => _displayName;
  int get avatarColor => _avatarColor;
  double get masterGain => _masterGain;
  double get micGain => _micGain;
  String get selfId => _selfId;
  double get duckFactor => _duckFactor;
  double get gateThreshold => _gateNorm;
  // Back-compat alias used by SettingsScreen
  int get gateLevel => (_gateNorm * 1000).round();
  int get micLowCutHz => _micLowCutHz;
  int get micHighCutHz => _micHighCutHz;
  int get playbackLowCutHz => _playLowCutHz;
  int get playbackHighCutHz => _playHighCutHz;
  bool get echoSuppressEnabled => _echoEnabled;
  double get echoSuppressStrength => _echoStrength;
  int get echoThreshold => _echoThreshold;
  bool get jitterEnabled => _jitterEnabled;
  bool _autoFullDuplex = true;
  bool get autoFullDuplex => _autoFullDuplex;

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
    await _pushProcConfig();
  }

  Future<void> setDuckFactor(double f) async {
    await _ensurePrefs();
    _duckFactor = f.clamp(0.0, 1.0);
    await _prefs!.setDouble('duck_factor', _duckFactor);
  }

  // Back-compat setter (maps 0..1000 to 0..1)
  Future<void> setGateLevel(int level) async {
    await _ensurePrefs();
    _gateNorm = (level / 1000.0).clamp(0.0, 1.0);
    await _prefs!.setDouble('gate_norm', _gateNorm);
    await _pushProcConfig();
  }

  Future<void> setGateThreshold(double t) async {
    await _ensurePrefs();
    _gateNorm = t.clamp(0.0, 1.0);
    await _prefs!.setDouble('gate_norm', _gateNorm);
    await _pushProcConfig();
  }

  Future<void> setMicLowCutHz(int hz) async {
    await _ensurePrefs();
    _micLowCutHz = hz.clamp(0, _sampleRate ~/ 2 - 1);
    await _prefs!.setInt('mic_low_cut_hz', _micLowCutHz);
    _rebuildFilters();
    await _pushProcConfig();
  }

  Future<void> setMicHighCutHz(int hz) async {
    await _ensurePrefs();
    _micHighCutHz = hz.clamp(0, _sampleRate ~/ 2 - 1);
    await _prefs!.setInt('mic_high_cut_hz', _micHighCutHz);
    _rebuildFilters();
    await _pushProcConfig();
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

  Future<void> setEchoSuppressEnabled(bool enabled) async {
    await _ensurePrefs();
    _echoEnabled = enabled;
    await _prefs!.setBool('echo_enabled', _echoEnabled);
    await _pushProcConfig();
  }

  Future<void> setEchoSuppressStrength(double strength) async {
    await _ensurePrefs();
    _echoStrength = strength.clamp(0.0, 1.0);
    await _prefs!.setDouble('echo_strength', _echoStrength);
    await _pushProcConfig();
  }

  Future<void> setEchoThreshold(int level) async {
    await _ensurePrefs();
    _echoThreshold = level.clamp(0, 5000);
    await _prefs!.setInt('echo_threshold', _echoThreshold);
    await _pushProcConfig();
  }

  Future<void> setJitterEnabled(bool enabled) async {
    await _ensurePrefs();
    _jitterEnabled = enabled;
    await _prefs!.setBool('jitter_enabled', _jitterEnabled);
  }

  Future<void> setAutoFullDuplex(bool enabled) async {
    await _ensurePrefs();
    _autoFullDuplex = enabled;
    await _prefs!.setBool('auto_full_duplex', _autoFullDuplex);
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
            k == 'gate_norm' ||
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
    _gateNorm = 0.18;
    _micLowCutHz = 0;
    _micHighCutHz = 0;
    _playLowCutHz = 0;
    _playHighCutHz = 0;
    _echoEnabled = false;
    _echoStrength = 0.6;
    _echoThreshold = 600;
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
    // Android 13+ notifications for status
    try { await Permission.notification.request(); } catch (_) {}
    final ok = mic.isGranted;
    if (!ok) _log('Permission micro refusée');
    return ok;
  }

  void setMode(ConnectionMode mode) {
    _mode = mode;
    _log('Mode sélectionné: ${_mode.name}');
    _emitPeers();
    _updateNotification();
  }

  void setInternetEndpoint({required String host, int? port}) {
    _serverHost = host.trim();
    if (port != null) _serverPort = port;
    _serverAddress = null;
    _log('Endpoint Internet: $_serverHost:$_serverPort');
    _emitPeers();
    _updateNotification();
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
    // Start audio processor isolate
    await _proc.start(AudioProcessorConfig(
      sampleRate: _sampleRate,
      micLowCutHz: _micLowCutHz,
      micHighCutHz: _micHighCutHz,
      gateNorm: _gateNorm,
      echoEnabled: _echoEnabled,
      echoStrength: _echoStrength,
      echoThreshold: _echoThreshold,
      micGain: _micGain,
    ));

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
    await _updateNotification();
    // Ensure Android foreground service running to keep audio between screens
    await _ensureFgService();
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
    final micQueue = <Uint8List>[];
    bool processing = false;
    Future<void> drain() async {
      if (processing) return; processing = true;
      while (micQueue.isNotEmpty) {
        final chunk = micQueue.removeAt(0);
        try {
          final res = await _proc.process(chunk, _rxEma);
          if (res == null || res.pcm.isEmpty) continue;
          _micLevelC.add(res.micLevel.clamp(0.0, 1.0));
          final idBytes = utf8.encode(_selfId);
          final headerLen = 4 + idBytes.length + 2 + 4;
          final data = Uint8List(headerLen + res.pcm.length);
          final b = data.buffer.asUint8List();
          b[0] = 0x49; b[1] = 0x43; b[2] = 0x02; b[3] = idBytes.length & 0xFF;
          b.setRange(4, 4 + idBytes.length, idBytes);
          final seq = _txSeq & 0xFFFF; _txSeq = (_txSeq + 1) & 0xFFFF;
          final ts = DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF;
          final bd = ByteData.view(b.buffer);
          final offSeq = 4 + idBytes.length;
          bd.setUint16(offSeq, seq, Endian.little);
          bd.setUint32(offSeq + 2, ts, Endian.little);
          b.setRange(offSeq + 6, data.length, res.pcm);
          if (_mode == ConnectionMode.lan) {
            for (final p in _lanPeers.values) { _audioSock?.send(data, p.address, p.port); }
          } else {
            final dst = _serverAddress; if (dst != null) _audioSock?.send(data, dst, _serverPort);
          }
        } catch (e) { _log('Erreur envoi UDP: $e'); }
      }
      processing = false;
    }
    _micSub = stream.listen((Uint8List chunk) {
      if (chunk.isEmpty) return;
      if (micQueue.length < 8) micQueue.add(chunk);
      unawaited(drain());
    });
    _isTalking = true;
    _log('Capture micro démarrée');
    await _updateNotification();
  }

  Future<void> stopTalking() async {
    await _micSub?.cancel();
    _micSub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    _isTalking = false;
    _log('Capture micro arrêtée');
    await _updateNotification();
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
    _proc.stop();
    _jb?.stop();
    _jb = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _initialized = false;
    _lanPeers.clear();
    _lanLastSeen.clear();
    _netPeers.clear();
    _emitPeers();
    _log('Intercom arrêté');
    await _stopFgService();
  }

  void dispose() {
    _logC.close();
    _peersC.close();
    _micLevelC.close();
    _outLevelC.close();
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

  // Mic gating handled in AudioProcessor isolate; no additional gate here.

  // ===== UDP: audio reception =====
  DateTime _lastRxLog = DateTime.fromMillisecondsSinceEpoch(0);
  void _onAudioUdp(RawSocketEvent ev) {
    if (ev != RawSocketEvent.read) return;
    final dg = _audioSock?.receive();
    if (dg == null) return;
    final bytes = dg.data;

    // Control messages (PEERS / PRES / GONE)
    try {
      // Fast-path: only decode UTF-8 if it's clearly a control message starting with 'ICSV1|'
      if (bytes.length >= 6 &&
          bytes[0] == 0x49 /* I */ &&
          bytes[1] == 0x43 /* C */ &&
          bytes[2] == 0x53 /* S */ &&
          bytes[3] == 0x56 /* V */ &&
          bytes[4] == 0x31 /* 1 */ &&
          bytes[5] == 0x7C /* '|' */) {
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

    // Audio packet: v1 IC|01|idLen|id|pcm16  OR v2 IC|02|idLen|id|seq:uint16|ts:uint32|pcm16
    Uint8List payload;
    int? seq;
    try {
      if (bytes.length >= 4 && bytes[0] == 0x49 && bytes[1] == 0x43) {
        final ver = bytes[2] & 0xFF;
        if (ver == 0x01) {
          final idLen = bytes[3] & 0xFF;
          if (bytes.length >= 4 + idLen) {
            final senderId = utf8.decode(bytes.sublist(4, 4 + idLen));
            if (senderId == _selfId) return; // mix-minus
            payload = bytes.sublist(4 + idLen);
          } else {
            payload = bytes;
          }
        } else if (ver == 0x02) {
          final idLen = bytes[3] & 0xFF;
          if (bytes.length >= 4 + idLen + 6) {
            final senderId = utf8.decode(bytes.sublist(4, 4 + idLen));
            if (senderId == _selfId) return;
            final offSeq = 4 + idLen;
            final bd = ByteData.sublistView(bytes);
            seq = bd.getUint16(offSeq, Endian.little);
            // final ts = bd.getUint32(offSeq + 2, Endian.little); // reserved
            payload = bytes.sublist(offSeq + 6);
          } else {
            payload = bytes;
          }
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
        if (bytes.length >= 4 && bytes[0] == 0x49 && bytes[1] == 0x43) {
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
      // Apply ducking as attenuation when talking (duckFactor is attenuation)
      final double duckFactor = _isTalking ? (1.0 - _duckFactor) : 1.0;
      final double globalGain = _masterGain * duckFactor;
      if (globalGain != 1.0) {
        toPlay = _applyGainPcm16(Uint8List.fromList(toPlay), globalGain);
      }
      if (_jitterEnabled) {
        _jb ??= _JitterBuffer(sampleRate: _sampleRate, onDequeue: (chunk) {
          _native.write(chunk);
        });
        final jb = _jb;
        if (jb != null) {
          if (seq != null) {
            jb.enqueueWithSeq(seq, toPlay);
          } else {
            jb.enqueue(toPlay);
          }
        }
      } else {
        _native.write(toPlay);
      }

      // Update playback energy EMA for echo suppression and out-level
      try {
        final bd = ByteData.view(toPlay.buffer, 0, toPlay.lengthInBytes);
        int count = 0;
        int sum = 0;
        for (int i = 0; i < toPlay.lengthInBytes; i += 2) {
          int s = bd.getInt16(i, Endian.little);
          if (s < 0) s = -s;
          sum += s;
          count++;
        }
        if (count > 0) {
          final avg = sum / count;
          _rxEma = _rxEma * (1 - _rxEmaAlpha) + avg * _rxEmaAlpha;
          final double outLevel = (_rxEma / 32768.0).clamp(0.0, 1.0);
          _outLevelC.add(outLevel);
        }
      } catch (_) {}
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
    _updateNotification();
  }

  Future<void> _updateNotification() async {
    try {
      final int peers = (_mode == ConnectionMode.internet) ? _netPeers.length : _lanPeers.length;
      final String title = 'Intercom actif • ${_mode.name.toUpperCase()}';
      final String body = 'Mic: ${_isTalking ? 'ON' : 'OFF'} • Peers: $peers • Gain: ${_masterGain.toStringAsFixed(2)}';
      // Single notification via foreground service (avoid duplicate local notifications)
      await _FgService.start(title: title, body: body);
    } catch (_) {}
  }

  Future<void> _ensureFgService() async {
    final int peers = (_mode == ConnectionMode.internet) ? _netPeers.length : _lanPeers.length;
    final String title = 'Intercom actif • ${_mode.name.toUpperCase()}';
    final String body = 'Mic: ${_isTalking ? 'ON' : 'OFF'} • Peers: $peers';
    await _FgService.start(title: title, body: body);
  }

  Future<void> _stopFgService() async { await _FgService.stop(); }

  void _rebuildFilters() {
    _fPlayHP = (_playLowCutHz > 0)
        ? _Biquad.highPass(_sampleRate.toDouble(), _playLowCutHz.toDouble())
        : null;
    _fPlayLP = (_playHighCutHz > 0)
        ? _Biquad.lowPass(_sampleRate.toDouble(), _playHighCutHz.toDouble())
        : null;
  }

  Future<void> _pushProcConfig() async {
    try {
      await _proc.update(AudioProcessorConfig(
        sampleRate: _sampleRate,
        micLowCutHz: _micLowCutHz,
        micHighCutHz: _micHighCutHz,
        gateNorm: _gateNorm,
        echoEnabled: _echoEnabled,
        echoStrength: _echoStrength,
        echoThreshold: _echoThreshold,
        micGain: _micGain,
      ));
    } catch (_) {}
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

// ===== Simple jitter buffer (ordered by seq, basic) =====
class _JitterBuffer {
  final int sampleRate;
  final void Function(Uint8List) onDequeue;
  final List<Uint8List> _queue = <Uint8List>[]; // fallback FIFO
  Timer? _timer;
  int? _frameBytes; // learned from first packet
  final Map<int, Uint8List> _buffer = <int, Uint8List>{};
  int? _expected;
  final int _maxBuffer = 10;
  int _target = 3; // target frames buffered

  _JitterBuffer({required this.sampleRate, required this.onDequeue});

  void enqueue(Uint8List chunk) {
    if (chunk.isEmpty) return;
    _queue.add(chunk);
    _frameBytes ??= chunk.lengthInBytes;
    _ensureTimer();
  }

  void enqueueWithSeq(int seq, Uint8List chunk) {
    _buffer[seq & 0xFFFF] = chunk;
    if (_expected == null) {
      // choose the smallest seq as starting point
      _expected = _buffer.keys.isEmpty ? (seq & 0xFFFF) : _buffer.keys.reduce((a, b) => a <= b ? a : b);
    }
    _ensureTimer();
  }

  void _ensureTimer() {
    final bytes = _frameBytes;
    // Estimate frame duration from bytes (PCM16 mono)
    final int frameSamples = (bytes != null && bytes > 0) ? (bytes ~/ 2) : (sampleRate ~/ 50); // ~20ms fallback
    final int frameMs = (1000 * frameSamples ~/ sampleRate).clamp(5, 60);
    _timer ??= Timer.periodic(Duration(milliseconds: frameMs), (_) {
      if (_buffer.isNotEmpty) {
        // Ordered drain by expected sequence
        _expected ??= _buffer.keys.reduce((a, b) => a <= b ? a : b);
        final exp = _expected! & 0xFFFF;
        final chunk = _buffer.remove(exp);
        if (chunk != null) {
          onDequeue(chunk);
          _expected = (exp + 1) & 0xFFFF;
        } else {
          // If buffer grows too much, reduce latency by popping the smallest sequence
          if (_buffer.length > _maxBuffer) {
            final minKey = _buffer.keys.reduce((a, b) => a <= b ? a : b);
            final forced = _buffer.remove(minKey);
            if (forced != null) onDequeue(forced);
            _expected = (minKey + 1) & 0xFFFF;
          }
        }
        // Simple adaptation: if buffer still much larger than target, dequeue an extra frame
        if (_buffer.length > _target + 3) {
          final nextKey = _buffer.keys.reduce((a, b) => a <= b ? a : b);
          final forced2 = _buffer.remove(nextKey);
          if (forced2 != null) onDequeue(forced2);
          _expected = (nextKey + 1) & 0xFFFF;
        }
        // If buffer often underflows, increase target slightly; if often large, decrease a bit.
        if (_buffer.length <= 1 && _target < 5) {
          _target++;
        } else if (_buffer.length > 6 && _target > 2) {
          _target--;
        }
      } else if (_queue.isNotEmpty) {
        // Fallback FIFO if no seq info
        final chunk = _queue.removeAt(0);
        onDequeue(chunk);
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _queue.clear();
    _frameBytes = null;
    _buffer.clear();
    _expected = null;
  }
}

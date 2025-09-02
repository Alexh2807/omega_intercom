// lib/intercom_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class PeerInfo {
  final InternetAddress address;
  final String name;
  const PeerInfo(this.address, this.name);
}

class IntercomService {
  static const String _serviceType = '_omega-intercom._tcp';
  static const int _port = 55667;
  static const String _helloHeader = 'OMEGA-INTERCOM|HELLO|';
  static const String _byeHeader = 'OMEGA-INTERCOM|BYE|';

  // Réseau
  RawDatagramSocket? _socket;
  final Set<InternetAddress> _peers = <InternetAddress>{};
  final Map<InternetAddress, String> _peerNames = <InternetAddress, String>{};
  Set<InternetAddress> _selfIps = <InternetAddress>{};

  // Audio I/O
  final AudioRecorder _recorder = AudioRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  StreamSubscription<Uint8List>? _micSub;

  // mDNS
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;

  // Handshake
  Timer? _helloTimer;
  String _deviceName = 'Omega Intercom';
  final String _nodeId = 'n' + DateTime.now().millisecondsSinceEpoch.toRadixString(36);

  // Streams
  final StreamController<int> _peersCountController = StreamController<int>.broadcast();
  final StreamController<List<PeerInfo>> _peersController = StreamController<List<PeerInfo>>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();

  Stream<int> get peersCountStream => _peersCountController.stream;
  Stream<List<PeerInfo>> get peersStream => _peersController.stream;
  Stream<String> get logStream => _logController.stream;

  void _log(String message) {
    final ts = DateTime.now().toIso8601String();
    final line = '[$ts] $message';
    if (kDebugMode) print('[Intercom] $line');
    _logController.add(line);
  }

  Future<void> init() async {
    _log('Initializing intercom service…');

    // Permission micro
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      throw Exception('Microphone permission denied');
    }

    // Socket UDP
    _socket ??= await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _port,
      reuseAddress: true,
      reusePort: true,
    );
    _socket!.broadcastEnabled = true;
    _socket!.readEventsEnabled = true;
    _socket!.listen(_onUdpData);

    // Collecte des IP locales (IPv4)
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      _selfIps = ifaces.expand((i) => i.addresses).toSet();
      _log('Local IPv4s: ${_selfIps.map((e) => e.address).join(', ')}');
    } catch (e) {
      _log('Failed to list local interfaces: $e');
    }

    // Préparer le player en mode stream
    await _player.openPlayer();
    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: 16000,
      // Réduire la taille du tampon pour diminuer la latence perçue
      bufferSize: 512,
      interleaved: true,
    );
    _log('Audio player ready (PCM16/16kHz/mono).');

    // Nom d'annonce & handshake
    try {
      final wifiName = await NetworkInfo().getWifiName();
      _deviceName = (wifiName ?? 'Omega Intercom')
          .replaceAll(RegExp(r'[^A-Za-z0-9 _\-\.]'), '');
      if (_deviceName.isEmpty) _deviceName = 'Omega Intercom';
    } catch (_) {}

    _startHelloLoop();

    // mDNS : annonce + découverte
    await _startMdns();
  }

  // Méthode attendue par ton UI (Active l’intercom)
  Future<void> start() async {
    await init();
    await startTalking();
  }

  // Capture micro + envoi UDP
  Future<void> startTalking() async {
    if (await _recorder.hasPermission() != true) {
      final ok = await Permission.microphone.request();
      if (!ok.isGranted) throw Exception('Microphone permission denied');
    }

    const cfg = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      // 16 kHz reste lisible tout en limitant la latence.
      // Pour encore moins de latence, on peut monter à 24000.
      sampleRate: 16000,
      numChannels: 1,
      bitRate: 256000, // ignoré en PCM
    );

    final stream = await _recorder.startStream(cfg);
    _log('Microphone stream started (PCM16/16kHz/mono).');
    _micSub?.cancel();
    _micSub = stream.listen((Uint8List chunk) {
      if (_peers.isEmpty) {
        // Fallback: broadcast si aucun pair connu
        try {
          _socket?.send(chunk, InternetAddress('255.255.255.255'), _port);
        } catch (e) {
          _log('UDP broadcast error: $e');
        }
      }
      for (final peer in _peers) {
        try {
          _socket?.send(chunk, peer, _port);
        } catch (e) {
          _log('UDP send error to ${peer.address}: $e');
        }
      }
    });
  }

  Future<void> stopTalking() async {
    await _micSub?.cancel();
    _micSub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  void _onUdpData(RawSocketEvent ev) {
    if (ev != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;

    final src = datagram.address;
    if (_selfIps.contains(src)) return; // ignorer nos propres paquets

    // Détecter un handshake court (texte)
    if (datagram.data.length <= 200) {
      try {
        final msg = utf8.decode(datagram.data, allowMalformed: true);
        if (msg.startsWith(_helloHeader)) {
          final parts = msg.split('|');
          final name = parts.length >= 4 ? parts[3] : src.address;
          _peers.add(src);
          _peerNames[src] = name;
          _peersCountController.add(_peers.length);
          _peersController.add(_peerNames.entries
              .map((e) => PeerInfo(e.key, e.value))
              .toList(growable: false));
          _log('HELLO from $name ${src.address}');
          return;
        } else if (msg.startsWith(_byeHeader)) {
          _peers.remove(src);
          _peerNames.remove(src);
          _peersCountController.add(_peers.length);
          _peersController.add(_peerNames.entries
              .map((e) => PeerInfo(e.key, e.value))
              .toList(growable: false));
          _log('BYE from ${src.address}');
          return;
        }
      } catch (_) {}
    }

    // Sinon: paquet audio PCM16
    _player.uint8ListSink?.add(datagram.data);
    _log('Received ${datagram.data.length} bytes from ${src.address}');
  }

  Future<void> _startMdns() async {
    _broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: _deviceName,
        type: _serviceType,
        port: _port,
      ),
    );
    await _broadcast!.initialize();
    await _broadcast!.start();

    _discovery = BonsoirDiscovery(type: _serviceType);
    await _discovery!.initialize();
    _discovery!.eventStream?.listen((event) async {
      if (event is BonsoirDiscoveryServiceResolvedEvent) {
        final srv = event.service;
        final host = srv.host;
        if (host != null && host.isNotEmpty) {
          try {
            final addresses = await InternetAddress.lookup(host);
            for (final addr in addresses.where((a) => a.type == InternetAddressType.IPv4)) {
              if (_selfIps.contains(addr)) continue;
              _peers.add(addr);
              _peerNames[addr] = srv.name ?? host;
              _log('Peer discovered (mDNS): ${srv.name ?? host} -> ${addr.address}');
            }
          } catch (_) {}
        }
        _peersCountController.add(_peers.length);
        _peersController.add(_peerNames.entries
            .map((e) => PeerInfo(e.key, e.value))
            .toList(growable: false));
      } else if (event is BonsoirDiscoveryServiceLostEvent) {
        final srv = event.service;
        final host = srv.host;
        if (host != null && host.isNotEmpty) {
          try {
            final addresses = await InternetAddress.lookup(host);
            for (final addr in addresses.where((a) => a.type == InternetAddressType.IPv4)) {
              _peers.remove(addr);
              _peerNames.remove(addr);
              _log('Peer lost (mDNS): ${srv.name ?? host} -> ${addr.address}');
            }
          } catch (_) {}
        }
        _peersCountController.add(_peers.length);
        _peersController.add(_peerNames.entries
            .map((e) => PeerInfo(e.key, e.value))
            .toList(growable: false));
      }
    });
    await _discovery!.start();
  }

  void _startHelloLoop() {
    _sendHello();
    _helloTimer?.cancel();
    _helloTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sendHello());
  }

  void _sendHello() {
    try {
      final payload = utf8.encode('$_helloHeader$_nodeId|$_deviceName');
      _socket?.send(payload, InternetAddress('255.255.255.255'), _port);
      for (final p in _peers) {
        _socket?.send(payload, p, _port);
      }
    } catch (e) {
      _log('HELLO send error: $e');
    }
  }

  Future<void> stop() async {
    _log('Stopping intercom service…');
    await stopTalking();

    try {
      final bye = utf8.encode('$_byeHeader$_nodeId|$_deviceName');
      _socket?.send(bye, InternetAddress('255.255.255.255'), _port);
    } catch (_) {}

    _helloTimer?.cancel();
    _helloTimer = null;

    _socket?.close();
    _socket = null;

    await _player.stopPlayer();
    await _player.closePlayer();

    await _broadcast?.stop();
    await _discovery?.stop();

    _peers.clear();
    _peerNames.clear();
    _peersCountController.add(0);
    _peersController.add(const <PeerInfo>[]);
  }

  Future<bool> requestPermissions() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  void dispose() {
    _peersCountController.close();
    _peersController.close();
    _logController.close();
  }
}

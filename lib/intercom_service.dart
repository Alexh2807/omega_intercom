// lib/intercom_service.dart (WebRTC version)
import "dart:async";
import "dart:convert";
import "dart:io"; // For RawDatagramSocket
import "package:flutter/foundation.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:web_socket_channel/web_socket_channel.dart";


enum ConnectionMode { lan, internet }

// Peer model for WebRTC
class Peer {
  final String id;
  final String name;
  RTCPeerConnection? connection;
  RTCVideoRenderer renderer = RTCVideoRenderer();
  MediaStream? stream;

  Peer({required this.id, required this.name});

  Future<void> initialize() async {
    await renderer.initialize();
  }

  void dispose() {
    renderer.dispose();
    connection?.dispose();
  }
}

class IntercomService {
  // Singleton
  static final IntercomService _instance = IntercomService._internal();
  factory IntercomService() => _instance;
  IntercomService._internal();

  // Signaling
  String _serverUrl = "ws://93.1.78.21:55667"; // Default to public IP
  WebSocketChannel? _channel;
  HttpServer? _localServer; // For LAN mode
  RawDatagramSocket? _lanDiscoverySocket; // For LAN discovery
  Timer? _lanDiscoveryTimer; // For sending periodic LAN broadcasts
  String? _lanLeaderId; // ID of the discovered LAN leader

  // WebRTC
  final Map<String, Peer> _peers = {};
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  // Identity / prefs
  String _selfId = "";
  String _displayName = "Appareil";
  SharedPreferences? _prefs;
  bool _prefsLoaded = false;

  // State
  bool _initialized = false;
  bool _isMuted = false;
  ConnectionMode _mode = ConnectionMode.internet; // Default mode

  // UI streams
  final _logC = StreamController<String>.broadcast();
  final _peersC = StreamController<List<Peer>>.broadcast();
  final _muteStateC = StreamController<bool>.broadcast();
  final _lanStatusC = StreamController<String>.broadcast();

  Stream<String> get logStream => _logC.stream;
  Stream<List<Peer>> get peersStream => _peersC.stream;
  Stream<bool> get muteStateStream => _muteStateC.stream;
  Stream<String> get lanStatusStream => _lanStatusC.stream;

  bool get isInitialized => _initialized;
  bool get isMuted => _isMuted;
  RTCVideoRenderer get localRenderer => _localRenderer;

  void _log(String m) {
    if (kDebugMode) print("[Intercom] $m");
    _logC.add(m);
  }

  Future<void> _ensurePrefs() async {
    if (_prefsLoaded) return;
    _prefs = await SharedPreferences.getInstance();
    _displayName = _prefs!.getString("display_name") ?? _displayName;
    _prefsLoaded = true;
  }

  String get displayName => _displayName;
  Future<void> setDisplayName(String name) async {
    await _ensurePrefs();
    _displayName = name.trim().isEmpty ? "Utilisateur" : name.trim();
    await _prefs!.setString("display_name", _displayName);
  }

  Future<void> start({required ConnectionMode mode, String? host, int? port}) async {
    if (_initialized) return;
    _mode = mode;
    await _ensurePrefs();

    await _localRenderer.initialize();

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        "audio": true,
        "video": false,
      });
      _localRenderer.srcObject = _localStream;
      // Start with audio enabled for full-duplex
      _localStream?.getAudioTracks().forEach((track) => track.enabled = true);
      _isMuted = false;
      _muteStateC.add(_isMuted);
    } catch (e) {
      _log("Erreur getUserMedia: $e");
      return;
    }

    switch (_mode) {
      case ConnectionMode.internet:
        if (host != null && host.isNotEmpty) {
          _serverUrl = "ws://$host:${port ?? 55667}";
        }
        _connectToSignaling();
        break;
      case ConnectionMode.lan:
        _log("LAN mode selected. Discovering leader...");
        _lanStatusC.add("Searching for LAN leader...");
        _lanLeaderId = null; // Reset leader
        await _startLanDiscovery();

        // Add a timeout to check if a leader was found
        Future.delayed(const Duration(seconds: 10), () {
          if (_lanLeaderId == null) {
            _log("No LAN leader found after 10 seconds.");
            _lanStatusC.add("No LAN leader found. Please start the signaling server on one device.");
          }
        });
        break;
    }

    _initialized = true;
    _log("Intercom (WebRTC) demarre");
  }

  

  Future<void> _startLanDiscovery() async {
    _lanDiscoverySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _lanDiscoverySocket!.broadcastEnabled = true;
    _lanDiscoverySocket!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        Datagram? dg = _lanDiscoverySocket!.receive();
        if (dg != null) {
          final message = utf8.decode(dg.data);
          _log("Received LAN discovery: $message from ${dg.address.address}");
          try {
            final data = json.decode(message);
            if (data["type"] == "leader_announce" && data["id"] != _selfId) {
              _lanLeaderId = data["id"];
              _serverUrl = "ws://${dg.address.address}:${data["port"]}";
              _log("Discovered LAN leader: $_lanLeaderId at $_serverUrl");
              _lanStatusC.add("LAN leader found. Connecting...");
              _lanStatusC.add("LAN leader found. Connecting...");
              _lanDiscoveryTimer?.cancel(); // Stop broadcasting if leader found
              _connectToSignaling(); // Connect to the discovered leader
            }
          } catch (e) {
            _log("Error parsing LAN discovery message: $e");
          }
        }
      }
    });

    _lanDiscoveryTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final message = json.encode({
        "type": "leader_announce",
        "id": _selfId,
        "name": _displayName,
        "port": 55667, // Assuming local server runs on 55667
      });
      _lanDiscoverySocket!.send(utf8.encode(message), InternetAddress("255.255.255.255"), 50005);
      _log("Sent LAN discovery broadcast");
    });
  }

  void _connectToSignaling() {
    _log("Connexion au serveur de signalisation: $_serverUrl");
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      _channel!.stream.listen((message) {
        final data = json.decode(message);
        _handleSignalingMessage(data);
      }, onDone: () {
        _log("Deconnecte du serveur de signalisation");
        stop(); // Stop intercom if signaling disconnects
      }, onError: (error) {
        _log("Erreur de signalisation: $error");
        stop();
      });
    } catch (e) {
      _log("Impossible de se connecter au serveur de signalisation: $e");
      stop();
    }
  }

  void _handleSignalingMessage(Map<String, dynamic> data) {
    final type = data["type"];
    _log("Message recu: $type");

    switch (type) {
      case "welcome":
        _selfId = data["id"];
        final peers = data["peers"] as List<dynamic>;
        _log("Assigne ID: $_selfId. Pairs existants: ${peers.length}");
        
        for (final peerData in peers) {
          _createPeerConnection(peerData["id"], peerData["name"], createOffer: true);
        }

        _send({"type": "announce", "from": _selfId, "name": _displayName});
        break;
      case "peer-joined":
        _createPeerConnection(data["id"], data["name"], createOffer: false);
        break;
      case "peer-left":
        _removePeer(data["id"]);
        break;
      case "offer":
        _handleOffer(data["from"], data["sdp"]);
        break;
      case "answer":
        _handleAnswer(data["from"], data["sdp"]);
        break;
      case "candidate":
        _handleCandidate(data["from"], data["candidate"]);
        break;
      default:
        _log("Message de signalisation inconnu: $type");
    }
  }

  Future<void> _createPeerConnection(String peerId, String name, {required bool createOffer}) async {
    if (_peers.containsKey(peerId)) return;
    _log("Creation de la connexion pour le peer: $peerId ($name)");

    final peer = Peer(id: peerId, name: name);
    await peer.initialize();

    final config = {
      "iceServers": [
        {"urls": "stun:stun.l.google.com:19302"},
      ]
    };
    final pc = await createPeerConnection(config);

    pc.onIceCandidate = (candidate) {
      // ignore: unnecessary_null_comparison
      if (candidate == null) return;
      _send({
        "type": "candidate",
        "to": peerId,
        "from": _selfId,
        "candidate": candidate.toMap(),
      });
    };

    pc.onTrack = (event) {
      if (event.track.kind == "audio" && event.streams.isNotEmpty) {
        peer.stream = event.streams[0];
        peer.renderer.srcObject = peer.stream;
        _emitPeers();
      }
    };

    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    peer.connection = pc;
    _peers[peerId] = peer;
    _emitPeers();

    if (createOffer) {
      final description = await pc.createOffer();
      await pc.setLocalDescription(description);
      _send({
        "type": "offer",
        "to": peerId,
        "from": _selfId,
        "sdp": description.toMap(),
      });
    }
  }

  Future<void> _handleOffer(String fromId, dynamic sdp) async {
    final peer = _peers[fromId];
    if (peer == null || peer.connection == null) return;
    _log("Gestion de l'offre de: $fromId");

    final pc = peer.connection!;
    await pc.setRemoteDescription(RTCSessionDescription(sdp["sdp"], sdp["type"]));
    final description = await pc.createAnswer();
    await pc.setLocalDescription(description);

    _send({
      "type": "answer",
      "to": fromId,
      "from": _selfId,
      "sdp": description.toMap(),
    });
  }

  Future<void> _handleAnswer(String fromId, dynamic sdp) async {
    final peer = _peers[fromId];
    if (peer == null || peer.connection == null) return;
    _log("Gestion de la reponse de: $fromId");
    await peer.connection!.setRemoteDescription(RTCSessionDescription(sdp["sdp"], sdp["type"]));
  }

  Future<void> _handleCandidate(String fromId, dynamic candidate) async {
    final peer = _peers[fromId];
    if (peer != null && peer.connection != null) {
      await peer.connection!.addCandidate(RTCIceCandidate(
        candidate["candidate"],
        candidate["sdpMid"],
        candidate["sdpMLineIndex"],
      ));
    }
  }

  void _removePeer(String peerId) {
    final peer = _peers.remove(peerId);
    if (peer != null) {
      _log("Peer $peerId a quitte la session");
      peer.dispose();
      _emitPeers();
    }
  }

  void _send(Map<String, dynamic> data) {
    if (_channel?.sink != null) {
      _channel!.sink.add(json.encode(data));
    }
  }

  void _emitPeers() {
    _peersC.add(_peers.values.toList());
  }

  void toggleMute() {
    if (_localStream?.getAudioTracks().isNotEmpty ?? false) {
      final bool wasMuted = _isMuted;
      _isMuted = !wasMuted;
      _localStream!.getAudioTracks()[0].enabled = !_isMuted;
      _log(_isMuted ? "Micro coupe" : "Micro active");
      _muteStateC.add(_isMuted);
    }
  }

  Future<void> stop() async {
    if (!_initialized) return;
    _log("Arret de l'intercom...");

    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;
    await _localRenderer.dispose();

    for (final peer in _peers.values) {
      peer.dispose();
    }
    _peers.clear();
    await _channel?.sink.close();
    _channel = null;

    // Stop local server and discovery
    _localServer?.close();
    _localServer = null;
    _lanDiscoveryTimer?.cancel();
    _lanDiscoveryTimer = null;
    _lanDiscoverySocket?.close();
    _lanDiscoverySocket = null;
    _lanLeaderId = null;

    _initialized = false;
    _isMuted = false;
    _emitPeers();
    _muteStateC.add(_isMuted);
    _log("Intercom arrete");
  }

  void dispose() {
    _logC.close();
    _peersC.close();
    _muteStateC.close();
    _lanStatusC.close();
  }
}
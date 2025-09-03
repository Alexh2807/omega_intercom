import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:omega_intercom/intercom_service.dart';



class IntercomScreen extends StatefulWidget {
  const IntercomScreen({super.key});

  @override
  State<IntercomScreen> createState() => _IntercomScreenState();
}

class _IntercomScreenState extends State<IntercomScreen> {
  final IntercomService _intercomService = IntercomService();
  bool _isIntercomActive = false;
  bool _isMuted = true;
  String _statusText = "Intercom désactivé";
  final List<String> _logs = <String>[];
  StreamSubscription<String>? _logSub;
  StreamSubscription<bool>? _muteSub;
  Timer? _logFlushTimer;
  final List<String> _pendingLogs = <String>[];

  ConnectionMode _mode = ConnectionMode.lan;
  final TextEditingController _hostCtrl = TextEditingController(text: '93.1.78.21');
  final TextEditingController _portCtrl = TextEditingController(text: '55667');

  @override
  void initState() {
    super.initState();
    _isIntercomActive = _intercomService.isInitialized;
    _isMuted = _intercomService.isMuted;
    _updateStatusText();

    if (_isIntercomActive) {
      _subscribeToStreams();
    }
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _muteSub?.cancel();
    _logFlushTimer?.cancel();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _subscribeToStreams() {
    _logSub?.cancel();
    _logSub = _intercomService.logStream.listen((line) {
      _pendingLogs.add(line);
      _logFlushTimer ??= Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted || _pendingLogs.isEmpty) return;
        setState(() {
          _logs.addAll(_pendingLogs);
          _pendingLogs.clear();
          if (_logs.length > 200) {
            _logs.removeRange(0, _logs.length - 200);
          }
        });
      });
    });

    _muteSub?.cancel();
    _muteSub = _intercomService.muteStateStream.listen((isMuted) {
      if (mounted) {
        setState(() {
          _isMuted = isMuted;
          _updateStatusText();
        });
      }
    });
  }

  void _updateStatusText() {
    if (!_isIntercomActive) {
      _statusText = "Intercom désactivé";
    } else {
      final modeText = _mode == ConnectionMode.lan ? "LAN" : "Internet";
      _statusText = "${_isMuted ? "Micro coupé" : "Actif"} ($modeText)";
    }
  }

  Color _colorForKey(String key) {
    int hash = key.hashCode;
    final r = 100 + (hash & 0x7F);
    final g = 100 + ((hash >> 7) & 0x7F);
    final b = 100 + ((hash >> 14) & 0x7F);
    return Color.fromARGB(255, r, g, b);
  }

  Future<void> _toggleIntercom() async {
    if (_isIntercomActive) {
      await _intercomService.stop();
      _logSub?.cancel();
      _muteSub?.cancel();
      _logSub = null;
      _muteSub = null;
      setState(() {
        _logs.clear();
        _isIntercomActive = false;
        _isMuted = true;
        _updateStatusText();
      });
      return;
    }

    await _intercomService.start(mode: _mode, host: _hostCtrl.text.trim(), port: int.tryParse(_portCtrl.text.trim()));
    _subscribeToStreams();

    setState(() {
      _isIntercomActive = true;
      _isMuted = _intercomService.isMuted;
      _updateStatusText();
    });
  }

  void _toggleMute() {
    if (!_isIntercomActive) return;
    _intercomService.toggleMute();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Omega Intercom (WebRTC)'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 30),
              Icon(
                _isIntercomActive ? (_isMuted ? Icons.mic_off : Icons.podcasts) : Icons.mic_off_outlined,
                size: 150,
                color: _isIntercomActive ? (_isMuted ? Colors.orange : Colors.green) : Colors.grey,
              ),
              const SizedBox(height: 20),
              Text(
                _statusText,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),

              // --- Mute Button ---
              if (_isIntercomActive)
                GestureDetector(
                  onTap: _toggleMute,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: _isMuted
                          ? Colors.redAccent
                          : Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withAlpha(51), blurRadius: 12, spreadRadius: 2, offset: const Offset(0, 6))],
                    ),
                    child: Icon(
                      _isMuted ? Icons.mic_off : Icons.mic,
                      size: 56,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              if (_isIntercomActive)
                const SizedBox(height: 12),
              if (_isIntercomActive)
                Text(
                  _isMuted
                      ? 'Micro coupé (touchez pour parler)'
                      : 'Micro actif (touchez pour couper)',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              const SizedBox(height: 20),

              // --- Connection Controls ---
              SegmentedButton<ConnectionMode>(
                segments: const [
                  ButtonSegment(value: ConnectionMode.lan, label: Text("LAN"), icon: Icon(Icons.wifi)),
                  ButtonSegment(value: ConnectionMode.internet, label: Text("Internet"), icon: Icon(Icons.public)),
                ],
                selected: <ConnectionMode>{_mode},
                onSelectionChanged: _isIntercomActive ? null : (newSelection) {
                  setState(() {
                    _mode = newSelection.first;
                  });
                },
              ),
              const SizedBox(height: 16),
              if (_mode == ConnectionMode.internet)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hostCtrl,
                        enabled: !_isIntercomActive,
                        decoration: const InputDecoration(
                          labelText: 'Hôte du serveur',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _portCtrl,
                        enabled: !_isIntercomActive,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _toggleIntercom,
                icon: Icon(_isIntercomActive ? Icons.stop : Icons.play_arrow),
                label: Text(_isIntercomActive ? 'Désactiver' : "Activer l'intercom"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  textStyle: const TextStyle(fontSize: 18),
                  backgroundColor: _isIntercomActive ? Colors.redAccent : Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // --- Peers List ---
              if (_isIntercomActive)
                StreamBuilder<List<Peer>>(
                  stream: _intercomService.peersStream,
                  initialData: const <Peer>[],
                  builder: (context, snapshot) {
                    final peers = snapshot.data ?? const <Peer>[];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Participants connectés: ${peers.length}'),
                        const SizedBox(height: 8),
                        if (peers.isNotEmpty)
                          Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: peers.length,
                              itemBuilder: (context, index) {
                                final p = peers[index];
                                final initial = (p.name.isNotEmpty ? p.name[0] : 'P').toUpperCase();
                                final color = _colorForKey(p.id);
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    backgroundColor: color.withAlpha(217),
                                    foregroundColor: Colors.white,
                                    child: Text(initial),
                                  ),
                                  title: Text(p.name.isEmpty ? 'Peer ${p.id}' : p.name),
                                  trailing: SizedBox(
                                    width: 1,
                                    height: 1,
                                    child: RTCVideoView(p.renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),

              const SizedBox(height: 16),

              // --- Logs ---
              if (_isIntercomActive)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Logs'),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _logs.isEmpty
                          ? const Center(child: Text('En attente de logs…'))
                          : ListView.builder(
                              itemCount: _logs.length,
                              itemBuilder: (context, index) {
                                return Text(
                                  _logs[index],
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontFamily: 'monospace'),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              const SizedBox(height: 30),
              // Hidden RTCVideoView for local audio feedback (optional)
              SizedBox(width: 0, height: 0, child: RTCVideoView(_intercomService.localRenderer)),
            ],
          ),
        ),
      ),
    );
  }
}
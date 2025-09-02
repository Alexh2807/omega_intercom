import 'dart:async';
import 'package:flutter/material.dart';
import 'package:omega_intercom/intercom_service.dart';
import 'package:omega_intercom/settings_screen.dart';

class IntercomScreen extends StatefulWidget {
  const IntercomScreen({super.key});

  @override
  State<IntercomScreen> createState() => _IntercomScreenState();
}

class _IntercomScreenState extends State<IntercomScreen> {
  final IntercomService _intercomService = IntercomService();
  bool _isIntercomActive = false;
  bool _isTalking = false;
  String _statusText = 'Intercom désactivé';
  final List<String> _logs = <String>[];
  StreamSubscription<String>? _logSub;

  ConnectionMode _mode = ConnectionMode.lan;
  final TextEditingController _hostCtrl = TextEditingController(text: '93.1.78.21');
  final TextEditingController _portCtrl = TextEditingController(text: '55667');
  final TextEditingController _aliasCtrl = TextEditingController();

  @override
  void dispose() {
    _logSub?.cancel();
    _intercomService.stop();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }


  Color _colorForKey(String key) {
    int hash = 0;
    for (int i = 0; i < key.length; i++) {
      hash = (hash * 31 + key.codeUnitAt(i)) & 0x7fffffff;
    }
    final r = 100 + (hash & 0x7F);
    final g = 100 + ((hash >> 7) & 0x7F);
    final b = 100 + ((hash >> 14) & 0x7F);
    return Color.fromARGB(255, r, g, b);
  }

  void _showPeerControls(PeerInfo p) {
    final currentMuted = _intercomService.isMuted(p.id);
    double gain = _intercomService.gainOf(p.id);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        bool muted = currentMuted;
        return StatefulBuilder(
          builder: (context, setSt) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Paramètres de ${p.name}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Muet'),
                      Switch(
                        value: muted,
                        onChanged: (v) {
                          setSt(() => muted = v);
                          _intercomService.setMuted(p.id, v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Volume (0.0 - 2.0)'),
                  Slider(
                    value: gain,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    label: gain.toStringAsFixed(2),
                    onChanged: (v) {
                      setSt(() => gain = v);
                      _intercomService.setGain(p.id, v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fermer'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleIntercom() async {
    if (_isIntercomActive) {
      if (_isTalking) {
        try { await _intercomService.stopTalking(); } catch (_) {}
        _isTalking = false;
      }
      await _intercomService.stop();
      await _logSub?.cancel();
      _logSub = null;
      setState(() {
        _logs.clear();
        _isIntercomActive = false;
        _statusText = 'Intercom désactivé';
      });
      return;
    }

    final hasPermission = await _intercomService.requestPermissions();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('La permission du microphone est requise.'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    _intercomService.setMode(_mode);
    if (_mode == ConnectionMode.internet) {
      final host = _hostCtrl.text.trim();
      final port = int.tryParse(_portCtrl.text.trim());
      _intercomService.setInternetEndpoint(host: host, port: port);
    }

    await _intercomService.start();
    // Full duplex: start capturing immediately
    try {
      await _intercomService.startTalking();
      _isTalking = true;
    } catch (_) {}

    _logSub?.cancel();
    _logSub = _intercomService.logStream.listen((line) {
      setState(() {
        _logs.add(line);
        if (_logs.length > 200) {
          _logs.removeRange(0, _logs.length - 200);
        }
      });
    });

    setState(() {
      _isIntercomActive = true;
      _statusText = _mode == ConnectionMode.lan
          ? "Recherche des appareils sur le réseau local..."
          : "Connexion via Internet...";
    });
  }

  Future<void> _startTalking() async {
    if (!_isIntercomActive) return;
    try {
      await _intercomService.startTalking();
      if (mounted) {
        setState(() {
          _isTalking = true;
          _statusText = 'Maintenez pour parler (actif)';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur demarrage micro: $e')),
        );
      }
    }
  }

  Future<void> _stopTalking() async {
    try {
      await _intercomService.stopTalking();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isTalking = false;
        _statusText = "Relachez pour arreter de parler";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Omega Intercom'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Paramètres',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SettingsScreen(intercom: _intercomService)),
              );
            },
          )
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 30),
              Icon(
                _isIntercomActive ? Icons.podcasts : Icons.mic_off_outlined,
                size: 150,
                color: _isIntercomActive ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 20),

              Text(
                _statusText,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),

              if (_isIntercomActive)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTapDown: (_) { _startTalking(); },
                        onTapUp:   (_) { _stopTalking(); },
                        onTapCancel: () { _stopTalking(); },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: _isTalking
                                ? Colors.redAccent
                                : Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 12,
                                spreadRadius: 2,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Icon(
                            _isTalking ? Icons.mic : Icons.mic_none,
                            size: 56,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isTalking
                            ? 'Parole en cours… (maintenir)'
                            : 'Appuyez et maintenez pour parler',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mode de connexion'),
                    const SizedBox(height: 8),
                    SegmentedButton<ConnectionMode>(
                      segments: const [
                        ButtonSegment(
                          value: ConnectionMode.lan,
                          label: Text('Local (LAN)'),
                          icon: Icon(Icons.wifi_tethering),
                        ),
                        ButtonSegment(
                          value: ConnectionMode.internet,
                          label: Text('Internet'),
                          icon: Icon(Icons.public),
                        ),
                      ],
                      selected: <ConnectionMode>{_mode},
                      onSelectionChanged: _isIntercomActive
                          ? null
                          : (s) => setState(() => _mode = s.first),
                    ),
                    const SizedBox(height: 12),
                    if (_mode == ConnectionMode.internet)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _hostCtrl,
                              enabled: !_isIntercomActive,
                              decoration: const InputDecoration(
                                labelText: 'Hôte',
                                hintText: '93.1.78.21',
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
                                hintText: '55667',
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

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

              if (_isIntercomActive)
                StreamBuilder<List<PeerInfo>>(
                  stream: _intercomService.peersStream,
                  initialData: const <PeerInfo>[],
                  builder: (context, snapshot) {
                    final peers = snapshot.data ?? const <PeerInfo>[];
                    final total = 1 + peers.length;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_mode == ConnectionMode.lan)
                            Text('Participants connectés (LAN) : $total')
                          else ...[
                            Text('Internet: connecté à ${_hostCtrl.text}:${_portCtrl.text}'),
                            const SizedBox(height: 4),
                            Text('Participants connectés (Internet) : $total'),
                          ],
                          const SizedBox(height: 8),
                          if (_mode == ConnectionMode.lan || _mode == ConnectionMode.internet)
                            Container(
                              constraints: const BoxConstraints(maxHeight: 180),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: peers.length,
                                itemBuilder: (context, index) {
                                  final p = peers[index];
                                  final initial = (p.name.isNotEmpty ? p.name[0] : 'A').toUpperCase();
                                  final color = p.color != null ? Color(p.color!) : _colorForKey('${p.id}-${p.address.address}-${p.port}');
                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      backgroundColor: color.withValues(alpha: 0.85),
                                      foregroundColor: Colors.white,
                                      child: Text(initial),
                                    ),
                                    title: Text(p.name.isEmpty ? 'Appareil' : p.name),
                                    subtitle: Text(_mode == ConnectionMode.lan ? p.address.address : 'Internet'),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.settings_voice),
                                      onPressed: () => _showPeerControls(p),
                                      tooltip: 'Volume / Muet',
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                )
              else
                const Text('Participants connectés : 0'),

              const SizedBox(height: 16),

              if (_isIntercomActive)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
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
                            ? const Text('En attente de logs…')
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
                ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}




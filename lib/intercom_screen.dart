import 'dart:async';
import 'package:flutter/material.dart';
import 'package:omega_intercom/intercom_service.dart';

class IntercomScreen extends StatefulWidget {
  const IntercomScreen({super.key});

  @override
  State<IntercomScreen> createState() => _IntercomScreenState();
}

class _IntercomScreenState extends State<IntercomScreen> {
  final IntercomService _intercomService = IntercomService();
  bool _isIntercomActive = false;
  String _statusText = "Intercom désactivé";
  final List<String> _logs = <String>[];
  StreamSubscription<String>? _logSub;

  @override
  void dispose() {
    _logSub?.cancel();
    _intercomService.stop();
    super.dispose();
  }

  void _toggleIntercom() async {
    if (_isIntercomActive) {
      await _intercomService.stop();
      await _logSub?.cancel();
      _logSub = null;
      setState(() {
        _logs.clear();
        _isIntercomActive = false;
        _statusText = "Intercom désactivé";
      });
    } else {
      bool hasPermission = await _intercomService.requestPermissions();

      if (hasPermission) {
        await _intercomService.start();
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
          _statusText = "Recherche d'autres motards...";
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("La permission du microphone est requise."),
            backgroundColor: Colors.red,
          ));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Omega Intercom'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
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

              ElevatedButton.icon(
                onPressed: _toggleIntercom,
                icon: Icon(_isIntercomActive ? Icons.stop : Icons.play_arrow),
                label: Text(_isIntercomActive ? 'Désactiver' : 'Activer l\'intercom'),
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
                          Text("Participants connectés : $total"),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 140),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: peers.length,
                              itemBuilder: (context, index) {
                                final p = peers[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.smartphone),
                                  title: Text(p.name.isEmpty ? 'Appareil' : p.name),
                                  subtitle: Text(p.address.address),
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
                const Text("Participants connectés : 0"),

              const SizedBox(height: 16),

              if (_isIntercomActive)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Logs'),
                      const SizedBox(height: 8),
                      Container(
                        height: 200,
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant,
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


import 'package:flutter/material.dart';
import 'package:omega_intercom/intercom_service.dart';

class SettingsScreen extends StatefulWidget {
  final IntercomService intercom;
  const SettingsScreen({super.key, required this.intercom});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameCtrl;
  double _master = 1.0;
  double _mic = 1.0;
  int _color = 0xFF3F51B5;
  double _duck = 0.15;
  int _gate = 180;
  int _micLowCut = 0;
  int _micHighCut = 0;
  int _playLowCut = 0;
  int _playHighCut = 0;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.intercom.displayName);
    _master = widget.intercom.masterGain;
    _mic = widget.intercom.micGain;
    _color = widget.intercom.avatarColor;
    _duck = widget.intercom.duckFactor;
    _gate = widget.intercom.gateLevel;
    _micLowCut = widget.intercom.micLowCutHz;
    _micHighCut = widget.intercom.micHighCutHz;
    _playLowCut = widget.intercom.playbackLowCutHz;
    _playHighCut = widget.intercom.playbackHighCutHz;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parametres intercom'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: _reset,
            tooltip: 'Reinitialiser',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
            tooltip: 'Enregistrer',
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Color(_color),
                child: const Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom d\'affichage',
                    hintText: 'Ex: Alexis',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Couleur de l\'avatar'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _palette
                .map((c) => _ColorDot(
                      color: c,
                      selected: _color == c,
                      onTap: () => setState(() => _color = c),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          const Text('Volume general'),
          Slider(
            value: _master,
            min: 0.0,
            max: 2.0,
            divisions: 20,
            label: _master.toStringAsFixed(2),
            onChanged: (v) => setState(() => _master = v),
          ),
          const SizedBox(height: 8),
          const Text('Gain micro'),
          Slider(
            value: _mic,
            min: 0.0,
            max: 2.0,
            divisions: 20,
            label: _mic.toStringAsFixed(2),
            onChanged: (v) => setState(() => _mic = v),
          ),
          const SizedBox(height: 20),
          const Text('Reduction du larsen'),
          const SizedBox(height: 6),
          const Text('Attenuation pendant que je parle (ducker)', style: TextStyle(fontSize: 12, color: Colors.grey)),
          Slider(
            value: _duck,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            label: '${(_duck * 100).toStringAsFixed(0)}%',
            onChanged: (v) => setState(() => _duck = v),
          ),
          const SizedBox(height: 6),
          const Text('Seuil anti-larsen (gate) — plus haut = coupe plus', style: TextStyle(fontSize: 12, color: Colors.grey)),
          Slider(
            value: _gate.toDouble(),
            min: 0,
            max: 1000,
            divisions: 50,
            label: _gate.toString(),
            onChanged: (v) => setState(() => _gate = v.round()),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Equalizer - Micro (0 = désactivé)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Coupe-bas (Hz)'),
              Text(_micLowCut == 0 ? 'Off' : '${_micLowCut} Hz'),
            ],
          ),
          Slider(
            value: _micLowCut.toDouble(),
            min: 0,
            max: 400,
            divisions: 40,
            onChanged: (v) => setState(() => _micLowCut = v.round()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Coupe-haut (Hz)'),
              Text(_micHighCut == 0 ? 'Off' : '${_micHighCut} Hz'),
            ],
          ),
          Slider(
            value: _micHighCut.toDouble(),
            min: 0,
            max: 8000,
            divisions: 80,
            onChanged: (v) => setState(() => _micHighCut = v.round()),
          ),
          const SizedBox(height: 8),
          const Text('Equalizer - Lecture (0 = désactivé)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Coupe-bas (Hz)'),
              Text(_playLowCut == 0 ? 'Off' : '${_playLowCut} Hz'),
            ],
          ),
          Slider(
            value: _playLowCut.toDouble(),
            min: 0,
            max: 400,
            divisions: 40,
            onChanged: (v) => setState(() => _playLowCut = v.round()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Coupe-haut (Hz)'),
              Text(_playHighCut == 0 ? 'Off' : '${_playHighCut} Hz'),
            ],
          ),
          Slider(
            value: _playHighCut.toDouble(),
            min: 0,
            max: 8000,
            divisions: 80,
            onChanged: (v) => setState(() => _playHighCut = v.round()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.restore),
                  label: const Text('Reinitialiser'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    await widget.intercom.setDisplayName(_nameCtrl.text);
    await widget.intercom.setAvatarColor(_color);
    await widget.intercom.setMasterGain(_master);
    await widget.intercom.setMicGain(_mic);
    await widget.intercom.setDuckFactor(_duck);
    await widget.intercom.setGateLevel(_gate);
    await widget.intercom.setMicLowCutHz(_micLowCut);
    await widget.intercom.setMicHighCutHz(_micHighCut);
    await widget.intercom.setPlaybackLowCutHz(_playLowCut);
    await widget.intercom.setPlaybackHighCutHz(_playHighCut);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parametres enregistres')),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reset() async {
    await widget.intercom.resetSettings();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = widget.intercom.displayName;
      _color = widget.intercom.avatarColor;
      _master = widget.intercom.masterGain;
      _mic = widget.intercom.micGain;
      _duck = widget.intercom.duckFactor;
      _gate = widget.intercom.gateLevel;
      _micLowCut = widget.intercom.micLowCutHz;
      _micHighCut = widget.intercom.micHighCutHz;
      _playLowCut = widget.intercom.playbackLowCutHz;
      _playHighCut = widget.intercom.playbackHighCutHz;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Parametres reinitialises')),
    );
  }

  static const List<int> _palette = <int>[
    0xFFE53935, // red
    0xFFD81B60, // pink
    0xFF8E24AA, // purple
    0xFF5E35B1, // deep purple
    0xFF3949AB, // indigo
    0xFF1E88E5, // blue
    0xFF039BE5, // light blue
    0xFF00ACC1, // cyan
    0xFF00897B, // teal
    0xFF43A047, // green
    0xFF7CB342, // light green
    0xFFC0CA33, // lime
    0xFFFDD835, // yellow
    0xFFFFB300, // amber
    0xFFFB8C00, // orange
    0xFFF4511E, // deep orange
    0xFF6D4C41, // brown
    0xFF546E7A, // blue grey
  ];
}

class _ColorDot extends StatelessWidget {
  final int color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color(color),
          border: Border.all(color: selected ? Colors.black : Colors.white, width: 2),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
      ),
    );
  }
}

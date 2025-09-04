import 'package:flutter/material.dart';

class RouteOptions {
  bool avoidHighways;
  bool avoidTolls;
  bool avoidFerries;
  RouteOptions({
    this.avoidHighways = false,
    this.avoidTolls = false,
    this.avoidFerries = false,
  });

  RouteOptions copyWith({bool? avoidHighways, bool? avoidTolls, bool? avoidFerries}) => RouteOptions(
        avoidHighways: avoidHighways ?? this.avoidHighways,
        avoidTolls: avoidTolls ?? this.avoidTolls,
        avoidFerries: avoidFerries ?? this.avoidFerries,
      );
}

class RouteOptionsPanel extends StatefulWidget {
  final RouteOptions options;
  final ValueChanged<RouteOptions> onChanged;
  const RouteOptionsPanel({super.key, required this.options, required this.onChanged});

  @override
  State<RouteOptionsPanel> createState() => _RouteOptionsPanelState();
}

class _RouteOptionsPanelState extends State<RouteOptionsPanel> {
  late RouteOptions _opts;

  @override
  void initState() {
    super.initState();
    _opts = widget.options;
  }

  void _emit() => widget.onChanged(_opts);

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Options d\'itinéraire', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _chip('Éviter autoroutes', Icons.alt_route, _opts.avoidHighways, () {
              setState(() => _opts = _opts.copyWith(avoidHighways: !_opts.avoidHighways));
              _emit();
            }),
            _chip('Éviter péages', Icons.payments, _opts.avoidTolls, () {
              setState(() => _opts = _opts.copyWith(avoidTolls: !_opts.avoidTolls));
              _emit();
            }),
            _chip('Éviter ferries', Icons.directions_boat, _opts.avoidFerries, () {
              setState(() => _opts = _opts.copyWith(avoidFerries: !_opts.avoidFerries));
              _emit();
            }),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: FilterChip(
        label: Text(label),
        avatar: Icon(icon, color: selected ? Colors.white : Theme.of(context).colorScheme.primary),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: Theme.of(context).colorScheme.primary,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.black),
      ),
    );
  }
}


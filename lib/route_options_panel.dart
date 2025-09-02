import 'package:flutter/material.dart';

// Un modèle pour stocker l'état de nos options
class RouteOptions {
  bool avoidHighways;
  bool avoidTolls;
  bool avoidFerries;
  // On pourrait ajouter d'autres options ici, comme un mode "route sinueuse"

  RouteOptions({
    this.avoidHighways = false,
    this.avoidTolls = false,
    this.avoidFerries = false,
  });
}

class RouteOptionsPanel extends StatefulWidget {
  // Callback pour notifier l'écran principal des changements d'options
  final Function(RouteOptions) onOptionsChanged;

  const RouteOptionsPanel({super.key, required this.onOptionsChanged});

  @override
  State<RouteOptionsPanel> createState() => _RouteOptionsPanelState();
}

class _RouteOptionsPanelState extends State<RouteOptionsPanel> {
  final RouteOptions _options = RouteOptions();

  void _update() {
    // Appelle la fonction du parent pour lui transmettre les nouvelles options
    widget.onOptionsChanged(_options);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 80,
      left: 15,
      right: 15,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Options d\'itinéraire', style: TextStyle(fontWeight: FontWeight.bold)),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildOptionChip(
                    label: 'Autoroutes',
                    icon: Icons.add_road,
                    isSelected: !_options.avoidHighways,
                    onTap: () => _options.avoidHighways = !_options.avoidHighways,
                  ),
                  _buildOptionChip(
                    label: 'Péages',
                    icon: Icons.money_off,
                    isSelected: !_options.avoidTolls,
                    onTap: () => _options.avoidTolls = !_options.avoidTolls,
                  ),
                  _buildOptionChip(
                    label: 'Ferries',
                    icon: Icons.directions_boat,
                    isSelected: !_options.avoidFerries,
                    onTap: () => _options.avoidFerries = !_options.avoidFerries,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      label: Text(label),
      avatar: Icon(icon, color: isSelected ? Colors.white : Theme.of(context).colorScheme.primary),
      selected: isSelected,
      onSelected: (bool selected) {
        onTap();
        _update();
      },
      selectedColor: Theme.of(context).colorScheme.primary,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black,
      ),
    );
  }
}
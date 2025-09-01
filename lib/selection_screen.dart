// lib/selection_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_cube/flutter_cube.dart';

// Définir la classe Vehicle pour organiser les données de chaque véhicule
class Vehicle {
  final String name;
  final String objPath;
  final String description;

  const Vehicle({
    required this.name,
    required this.objPath,
    required this.description,
  });
}

// Données de base pour les véhicules disponibles (pour le moment, seulement la moto)
const List<Vehicle> availableVehicles = [
  Vehicle(
    name: 'motorcycle1',
    objPath: 'assets/objects/motorcycle1.obj',
    description: 'Une moto rapide et agile, parfaite pour la ville.',
  ),
  // Ajoutez d'autres véhicules ici au fur et à mesure
];

class VehicleSelectionScreen extends StatelessWidget {
  final ValueChanged<Vehicle> onVehicleSelected;
  final Vehicle currentVehicle;

  const VehicleSelectionScreen({
    Key? key,
    required this.onVehicleSelected,
    required this.currentVehicle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E), // Thème sombre
      appBar: AppBar(
        title: const Text(
          'Sélection du véhicule',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: availableVehicles.length,
        itemBuilder: (context, index) {
          final vehicle = availableVehicles[index];
          final isSelected = vehicle.name == currentVehicle.name;

          return _buildVehicleCard(context, vehicle, isSelected);
        },
      ),
    );
  }

  Widget _buildVehicleCard(
      BuildContext context, Vehicle vehicle, bool isSelected) {
    return GestureDetector(
      onTap: () {
        onVehicleSelected(vehicle);
        Navigator.pop(context);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16.0),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.2) : const Color(0xFF2C2C2C),
          borderRadius: BorderRadius.circular(15.0),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.transparent,
            width: 2.0,
          ),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: Colors.blue.withOpacity(0.5),
              spreadRadius: 2,
              blurRadius: 10,
            ),
          ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Aperçu du modèle 3D
              _buildModelPreview(vehicle),
              const SizedBox(width: 20),
              // Nom et description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.name.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      vehicle.description,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              // Icône de sélection
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: Colors.blue,
                  size: 30,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelPreview(Vehicle vehicle) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10.0),
        child: Cube(
          interactive: false,
          onSceneCreated: (Scene scene) {
            scene.world.add(Object(fileName: vehicle.objPath));
          },
        ),
      ),
    );
  }
}
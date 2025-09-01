// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import 'selection_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'OMEGA Intercom',
      home: MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;
  final Set<Marker> _markers = {};
  Position? _currentPosition;
  final LatLng _initialPosition = const LatLng(43.344444, 3.2125);
  StreamSubscription<Position>? _positionStreamSubscription;
  Vehicle _currentVehicle = availableVehicles[0];

  final String _darkMapStyle = '''
  [
    {
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#242f3e"
        }
      ]
    },
    ...
  ]
  ''';

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  void _checkLocationPermission() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      _startLocationStream();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission de localisation refusée.'),
          ),
        );
      }
    }
  }

  void _startLocationStream() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1,
    );
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      setState(() {
        _currentPosition = position;
      });
      mapController.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude),
        ),
      );
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    mapController.setMapStyle(_darkMapStyle);
  }

  void _openVehicleSelection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VehicleSelectionScreen(
          currentVehicle: _currentVehicle,
          onVehicleSelected: (selectedVehicle) {
            setState(() {
              _currentVehicle = selectedVehicle;
            });
          },
        ),
      ),
    );
  }

  // Fonction pour convertir les coordonnées géographiques en coordonnées d'écran
  Future<Offset?> _getScreenCoordinates(LatLng latLng) async {
    final screenLocation = await mapController.getScreenCoordinate(latLng);
    if (screenLocation != null) {
      // Ajustement pour centrer le modèle sur les coordonnées
      final Offset offset = Offset(screenLocation.x.toDouble(), screenLocation.y.toDouble());
      return offset;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // La carte Google Maps est le widget de base
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialPosition,
              zoom: 15.0,
            ),
            markers: _markers, // L'ensemble de marqueurs est vide pour les rendre invisibles
            onMapCreated: _onMapCreated,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          // Superposer le modèle 3D si la position est connue
          if (_currentPosition != null)
            FutureBuilder<Offset?>(
              future: _getScreenCoordinates(
                  LatLng(_currentPosition!.latitude, _currentPosition!.longitude)),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData &&
                    snapshot.data != null) {
                  final Offset screenOffset = snapshot.data!;
                  // Positionner le modèle 3D en utilisant les coordonnées d'écran
                  return Positioned(
                    left: screenOffset.dx - 50, // Ajuster pour centrer le modèle
                    top: screenOffset.dy - 50,  // Ajuster pour centrer le modèle
                    child: SizedBox(
                      width: 100, // Ajuster la taille
                      height: 100,
                      child: ModelViewer(
                        src: _currentVehicle.objPath, // Chemin vers votre fichier .obj
                        alt: _currentVehicle.name,
                        ar: false, // Désactiver la réalité augmentée
                        autoRotate: true,
                        cameraControls: false,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          // Bouton de sélection
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              heroTag: "settings_btn",
              onPressed: _openVehicleSelection,
              backgroundColor: const Color(0xFF2C2C2C),
              child: const Icon(Icons.directions_bike, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
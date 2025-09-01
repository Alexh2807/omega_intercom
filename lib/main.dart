// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_cube/flutter_cube.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;

import 'selection_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OMEGA Intercom',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const MapScreen(),
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
  final Set<Polyline> _polylines = {};
  final TextEditingController _destinationController = TextEditingController();
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
    _destinationController.dispose();
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

  Future<void> _searchAndNavigate() async {
    if (_currentPosition == null) return;
    final query = _destinationController.text;
    if (query.isEmpty) return;

    final geocodeUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1');
    final geocodeResponse =
        await http.get(geocodeUrl, headers: {'User-Agent': 'omega_intercom'});
    if (geocodeResponse.statusCode != 200) return;
    final geocodeData = jsonDecode(geocodeResponse.body);
    if (geocodeData.isEmpty) return;
    final destLat = double.parse(geocodeData[0]['lat']);
    final destLon = double.parse(geocodeData[0]['lon']);

    final routeUrl = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${_currentPosition!.longitude},'
        '${_currentPosition!.latitude};$destLon,$destLat?overview=full&geometries=geojson');
    final routeResponse = await http.get(routeUrl);
    if (routeResponse.statusCode != 200) return;
    final routeData = jsonDecode(routeResponse.body);
    final coords = routeData['routes'][0]['geometry']['coordinates'] as List;
    final List<LatLng> points =
        coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();

    setState(() {
      _markers.removeWhere((m) => m.markerId == const MarkerId('dest'));
      _markers.add(Marker(
          markerId: const MarkerId('dest'),
          position: LatLng(destLat, destLon)));
      _polylines
        ..clear()
        ..add(Polyline(
            polylineId: const PolylineId('route'),
            color: Colors.blue,
            width: 5,
            points: points));
    });

    mapController.animateCamera(
        CameraUpdate.newLatLngBounds(_boundsFromLatLngList(points), 50));
  }

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    final double x0 =
        list.map((p) => p.latitude).reduce((a, b) => math.min(a, b));
    final double x1 =
        list.map((p) => p.latitude).reduce((a, b) => math.max(a, b));
    final double y0 =
        list.map((p) => p.longitude).reduce((a, b) => math.min(a, b));
    final double y1 =
        list.map((p) => p.longitude).reduce((a, b) => math.max(a, b));
    return LatLngBounds(
        southwest: LatLng(x0, y0), northeast: LatLng(x1, y1));
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
            polylines: _polylines,
            onMapCreated: _onMapCreated,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: TextField(
                controller: _destinationController,
                decoration: InputDecoration(
                  hintText: 'Entrez votre destination',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _searchAndNavigate,
                  ),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _searchAndNavigate(),
              ),
            ),
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
                      child: Cube(
                        interactive: false,
                        onSceneCreated: (Scene scene) {
                          scene.world.add(Object(fileName: _currentVehicle.objPath));
                        },
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
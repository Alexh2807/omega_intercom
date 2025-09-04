import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:omega_intercom/route_options_panel.dart';
import 'package:omega_intercom/trip_info_panel.dart';
import 'package:omega_intercom/app_config.dart';
import 'package:omega_intercom/screens/intercom_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  CameraPosition _initial = const CameraPosition(target: LatLng(43.6108, 3.8767), zoom: 12); // Montpellier
  bool _dark = false;
  RouteOptions _opts = RouteOptions();
  String? _tripDuration;
  String? _tripDistance;
  bool _isRouteVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensurePermissions();
      await _centerOnMe();
      await _applyStyle();
    });
  }

  Future<void> _ensurePermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
  }

  Future<void> _centerOnMe() async {
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
    );
    final ctrl = await _controller.future;
    _initial = CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 15);
    ctrl.animateCamera(CameraUpdate.newCameraPosition(_initial));
    setState(() {});
  }

  Future<void> _applyStyle() async {
    // Style is now applied directly in GoogleMap widget
  }

  @override
  Widget build(BuildContext context) {
    _dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Carte & Itinéraire')),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (c) => _controller.complete(c),
            initialCameraPosition: _initial,
            style: _dark && AppConfig.darkMapStyle != null 
                ? AppConfig.darkMapStyle 
                : (!_dark && AppConfig.lightMapStyle != null ? AppConfig.lightMapStyle : null),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            compassEnabled: true,
            trafficEnabled: true,
          ),

          // Panels
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RouteOptionsPanel(
                  options: _opts,
                  onChanged: (o) => setState(() => _opts = o),
                ),
                const SizedBox(height: 12),
                if (_isRouteVisible && _tripDuration != null && _tripDistance != null)
                  TripInfoPanel(
                    duration: _tripDuration!,
                    distance: _tripDistance!,
                    onCancel: () => setState(() {
                      _isRouteVisible = false;
                      _tripDuration = null;
                      _tripDistance = null;
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IntercomScreen())),
        icon: const Icon(Icons.mic),
        label: const Text('Intercom'),
      ),
    );
  }
}
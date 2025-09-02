import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart' as placesSdk;
import 'package:omega_intercom/route_options_panel.dart';
import 'package:omega_intercom/trip_info_panel.dart';
// Nouvel import pour la page intercom
import 'package:omega_intercom/intercom_screen.dart';

const String GOOGLE_MAPS_API_KEY = "VOTRE_CLE_API_GOOGLE_MAPS";

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final Completer<GoogleMapController> _controller = Completer();
  final FocusNode _searchFocusNode = FocusNode();

  static const CameraPosition _kDefaultPosition = CameraPosition(
    target: LatLng(48.8566, 2.3522),
    zoom: 12,
  );

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  LatLng? _currentPosition;
  String? _mapStyle;

  RouteOptions _routeOptions = RouteOptions();
  String? _tripDuration;
  String? _tripDistance;
  bool _isRouteVisible = false;

  final places = placesSdk.FlutterGooglePlacesSdk(GOOGLE_MAPS_API_KEY);
  List<placesSdk.AutocompletePrediction> _predictions = [];
  String _selectedPlaceDescription = '';
  Timer? _debounce;

  // ... (Toutes les fonctions comme initState, _determinePosition, _getDirections etc. ne changent pas)
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMapStyle();
    _determinePosition();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {
      _loadMapStyle().then((_) async {
        final GoogleMapController controller = await _controller.future;
        controller.setMapStyle(_mapStyle);
      });
    });
  }

  Future<void> _loadMapStyle() async {
    final Brightness brightness = MediaQuery.of(context).platformBrightness;
    final String stylePath = brightness == Brightness.dark
        ? 'assets/map_styles/dark_mode.json'
        : 'assets/map_styles/light_mode.json';
    try {
      _mapStyle = await DefaultAssetBundle.of(context).loadString(stylePath);
    } catch (e) {
      _mapStyle = null;
    }
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showErrorDialog('Le service de localisation est désactivé.');
      return;
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showErrorDialog('La permission de localisation a été refusée.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _showErrorDialog('Permission de localisation refusée de manière permanente.');
      return;
    }
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _markers.clear();
      _markers.add(
        Marker(
          markerId: const MarkerId('currentPosition'),
          position: _currentPosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Ma Position'),
        ),
      );
    });
    _goToCurrentPosition();
  }

  Future<void> _goToCurrentPosition() async {
    if (_currentPosition == null) return;
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: _currentPosition!, zoom: 16.5, tilt: 30.0),
    ));
  }

  Future<void> _getDirections(LatLng destinationCoords, String destinationDescription) async {
    if (_currentPosition == null) return;

    String url = 'https://maps.googleapis.com/maps/api/directions/json?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}&destination=${destinationCoords.latitude},${destinationCoords.longitude}&key=$GOOGLE_MAPS_API_KEY';

    String restrictions = '';
    if (_routeOptions.avoidHighways) restrictions += 'highways|';
    if (_routeOptions.avoidTolls) restrictions += 'tolls|';
    if (_routeOptions.avoidFerries) restrictions += 'ferries|';
    if (restrictions.isNotEmpty) {
      url += '&avoid=${restrictions.substring(0, restrictions.length - 1)}';
    }

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['routes'].isNotEmpty) {
        final route = data['routes'][0];
        final leg = route['legs'][0];
        final points = route['overview_polyline']['points'];
        final List<LatLng> polylineCoordinates = _decodePolyline(points);

        setState(() {
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: polylineCoordinates,
              color: Colors.blueAccent,
              width: 6,
            ),
          );
          _markers.add(
            Marker(
              markerId: const MarkerId('destination'),
              position: destinationCoords,
              infoWindow: InfoWindow(title: destinationDescription),
            ),
          );
          _tripDistance = leg['distance']['text'];
          _tripDuration = leg['duration']['text'];
          _isRouteVisible = true;
          _selectedPlaceDescription = destinationDescription;
        });
      } else {
        _showErrorDialog('Aucun itinéraire trouvé avec ces options.');
      }
    } else {
      _showErrorDialog('Erreur lors du calcul de l\'itinéraire.');
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erreur'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  void _cancelRoute() {
    setState(() {
      _polylines.clear();
      _markers.removeWhere((m) => m.markerId.value == 'destination');
      _isRouteVisible = false;
      _tripDistance = null;
      _tripDuration = null;
      _selectedPlaceDescription = '';
      _predictions = [];
    });
  }

  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (value.isNotEmpty) {
        final result = await places.findAutocompletePredictions(value, countries: ['fr']);
        setState(() {
          _predictions = result.predictions;
        });
      } else {
        setState(() {
          _predictions = [];
        });
      }
    });
  }

  Future<void> _onPredictionTapped(placesSdk.AutocompletePrediction prediction) async {
    setState(() {
      _predictions = [];
      _searchFocusNode.unfocus();
    });

    final placeDetails = await places.fetchPlace(prediction.placeId, fields: [placesSdk.PlaceField.Location]);
    final location = placeDetails.place?.latLng;

    if (location != null) {
      final mapLatLng = LatLng(location.lat, location.lng);
      _getDirections(mapLatLng, prediction.fullText);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }


  // --- LA SEULE PARTIE MODIFIÉE EST LA FONCTION BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _kDefaultPosition,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
              controller.setMapStyle(_mapStyle);
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 15,
            left: 15,
            right: 15,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  child: TextField(
                    focusNode: _searchFocusNode,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Où allez-vous ?',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _isRouteVisible
                          ? IconButton(icon: const Icon(Icons.close), onPressed: _cancelRoute)
                          : null,
                    ),
                    controller: TextEditingController(text: _selectedPlaceDescription)..selection = TextSelection.fromPosition(TextPosition(offset: _selectedPlaceDescription.length)),
                  ),
                ),
                if (_predictions.isNotEmpty)
                  Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(15),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _predictions.length,
                      itemBuilder: (context, index) {
                        final prediction = _predictions[index];
                        return ListTile(
                          title: Text(prediction.primaryText),
                          subtitle: Text(prediction.secondaryText),
                          onTap: () => _onPredictionTapped(prediction),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          if (!_isRouteVisible)
            RouteOptionsPanel(
              onOptionsChanged: (options) {
                _routeOptions = options;
              },
            ),

          if (_isRouteVisible && _tripDistance != null && _tripDuration != null)
            TripInfoPanel(
              duration: _tripDuration!,
              distance: _tripDistance!,
              onCancel: _cancelRoute,
            ),
        ],
      ),
      // --- MODIFICATION DES BOUTONS FLOTTANTS ---
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'recenter_btn',
            onPressed: _goToCurrentPosition,
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),
          // BOUTON MODIFIÉ POUR OUVRIR LA PAGE INTERCOM
          FloatingActionButton(
            heroTag: 'intercom_btn',
            onPressed: () {
              // Action de navigation vers la nouvelle page
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const IntercomScreen()),
              );
            },
            backgroundColor: Theme.of(context).colorScheme.secondary,
            child: const Icon(Icons.podcasts),
          ),
        ],
      ),
    );
  }
}
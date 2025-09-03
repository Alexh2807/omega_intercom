import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// PLACES-DISABLED: import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart' as places_sdk;
import 'package:omega_intercom/route_options_panel.dart';
import 'package:omega_intercom/trip_info_panel.dart';
// Nouvel import pour la page intercom
import 'package:omega_intercom/intercom_screen.dart';
import 'package:omega_intercom/app_config.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final Completer<GoogleMapController> _controller = Completer();
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();

  static const CameraPosition _kDefaultPosition = CameraPosition(
    target: LatLng(48.8566, 2.3522),
    zoom: 12,
  );

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  LatLng? _currentPosition;
  String? _mapStyle;

  String? _tripDuration;
  String? _tripDistance;
  bool _isRouteVisible = false;

  RouteOptions _routeOptions = RouteOptions();

  
  // List<places_sdk.AutocompletePrediction> _predictions = [];
  
  // Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _determinePosition();
    // PLACES-DISABLED:
    // _searchCtrl.addListener(() {
    //   _onSearchChanged(_searchCtrl.text);
    // });
    // _initPlacesKey();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadMapStyle();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {
      _loadMapStyle();
    });
  }

  Future<void> _loadMapStyle() async {
    final Brightness brightness = MediaQuery.of(context).platformBrightness;
    _mapStyle = (brightness == Brightness.dark)
        ? AppConfig.darkMapStyle
        : AppConfig.lightMapStyle;
    if (mounted) setState(() {});
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
      _showErrorDialog(
          'Permission de localisation refusée de manière permanente.');
      return;
    }
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _markers.clear();
      _markers.add(
        Marker(
          markerId: const MarkerId('currentPosition'),
          position: _currentPosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure),
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

  // Future<void> _getDirections(LatLng destinationCoords,
  //     String destinationDescription) async {
  //   if (_currentPosition == null) return;

  //   final String key = _apiKey ?? '';
  //   String url = 'https://maps.googleapis.com/maps/api/directions/json?origin=${_currentPosition!
  //       .latitude},${_currentPosition!
  //       .longitude}&destination=${destinationCoords
  //       .latitude},${destinationCoords.longitude}&key=$key';

  //   String restrictions = '';
  //   if (_routeOptions.avoidHighways) restrictions += 'highways|';
  //   if (_routeOptions.avoidTolls) restrictions += 'tolls|';
  //   if (_routeOptions.avoidFerries) restrictions += 'ferries|';
  //   if (restrictions.isNotEmpty) {
  //     url += '&avoid=${restrictions.substring(0, restrictions.length - 1)}';
  //   }

  //   final response = await http.get(Uri.parse(url));

  //   if (response.statusCode == 200) {
  //     final data = json.decode(response.body);
  //     if (data['routes'].isNotEmpty) {
  //       final route = data['routes'][0];
  //       final leg = route['legs'][0];
  //       final points = route['overview_polyline']['points'];
  //       final List<LatLng> polylineCoordinates = _decodePolyline(points);

  //       setState(() {
  //         _polylines.clear();
  //         _polylines.add(
  //           Polyline(
  //             polylineId: const PolylineId('route'),
  //             points: polylineCoordinates,
  //             color: Colors.blueAccent,
  //             width: 6,
  //           ),
  //         );
  //         _markers.add(
  //           Marker(
  //             markerId: const MarkerId('destination'),
  //             position: destinationCoords,
  //             infoWindow: InfoWindow(title: destinationDescription),
  //           ),
  //         );
  //         _tripDistance = leg['distance']['text'];
  //         _tripDuration = leg['duration']['text'];
  //         _isRouteVisible = true;
  //       });
  //     } else {
  //       _showErrorDialog('Aucun itinéraire trouvé avec ces options.');
  //     }
  //   } else {
  //     _showErrorDialog("Erreur lors du calcul de l'itineraire.");
  //   }
  // }

  // List<LatLng> _decodePolyline(String encoded) {
  //   List<LatLng> points = [];
  //   int index = 0,
  //       len = encoded.length;
  //   int lat = 0,
  //       lng = 0;
  //   while (index < len) {
  //     int b,
  //         shift = 0,
  //         result = 0;
  //     do {
  //       b = encoded.codeUnitAt(index++) - 63;
  //       result |= (b & 0x1f) << shift;
  //       shift += 5;
  //     } while (b >= 0x20);
  //     int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
  //     lat += dlat;
  //     shift = 0;
  //     result = 0;
  //     do {
  //       b = encoded.codeUnitAt(index++) - 63;
  //       result |= (b & 0x1f) << shift;
  //       shift += 5;
  //     } while (b >= 0x20);
  //     int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
  //     lng += dlng;
  //     points.add(LatLng(lat / 1E5, lng / 1E5));
  //   }
  //   return points;
  // }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('Erreur'),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK')),
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
      // PLACES-DISABLED: _predictions = [];
    });
  }

  // PLACES-DISABLED:
  // void _onSearchChanged(String value) {
  //   if (_debounce?.isActive ?? false) _debounce!.cancel();
  //   _debounce = Timer(const Duration(milliseconds: 500), () async {
  //     if (value.isNotEmpty) {
  //       if (_places == null) return;
  //       final result = await _places!.findAutocompletePredictions(
  //           value, countries: ['fr']);
  //       setState(() {
  //         _predictions = result.predictions;
  //       });
  //     } else {
  //       setState(() {
  //         _predictions = [];
  //       });
  //     }
  //   });
  // }

  // PLACES-DISABLED:
  // Future<void> _onPredictionTapped(
  //     places_sdk.AutocompletePrediction prediction) async {
  //   setState(() {
  //     _predictions = [];
  //     _searchFocusNode.unfocus();
  //     _selectedPlaceDescription = prediction.fullText;
  //     _searchCtrl.text = _selectedPlaceDescription;
  //     _searchCtrl.selection = TextSelection.fromPosition(
  //         TextPosition(offset: _selectedPlaceDescription.length));
  //   });

  //   if (_places == null) return;
  //   final placeDetails = await _places!.fetchPlace(
  //       prediction.placeId, fields: [places_sdk.PlaceField.Location]);
  //   final location = placeDetails.place?.latLng;

  //   if (location != null) {
  //     final mapLatLng = LatLng(location.lat, location.lng);
  //     _getDirections(mapLatLng, prediction.fullText);
  //   }
  // }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchFocusNode.dispose();
    _searchCtrl.dispose();
    // PLACES-DISABLED: _debounce?.cancel();
    super.dispose();
  }

  // PLACES-DISABLED:
  // Future<void> _initPlacesKey() async {
  //   final key = await AppConfig.getPlacesKey();
  //   if (!mounted) return;
  //   setState(() {
  //     _apiKey = key;
  //     if (key != null && key.isNotEmpty) {
  //       _places = places_sdk.FlutterGooglePlacesSdk(key);
  //     }
  //   });
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_searchFocusNode.hasFocus) _searchFocusNode.unfocus();
          // PLACES-DISABLED: if (_predictions.isNotEmpty) setState(() => _predictions = []);
        },
        child: Stack(
          children: [
            RepaintBoundary(child: GoogleMap(
              mapType: MapType.normal,
              style: _mapStyle,
              initialCameraPosition: _kDefaultPosition,
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              onMapCreated: (GoogleMapController controller) {
                _controller.complete(controller);
              },
            )),
            Positioned(
              top: MediaQuery
                  .of(context)
                  .padding
                  .top + 15,
              left: 15,
              right: 15,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Theme
                          .of(context)
                          .cardColor,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 4))
                      ],
                    ),
                    child: Focus(
                        onFocusChange: (has) {
                          // PLACES-DISABLED:
                          // if (!has && _predictions.isNotEmpty) {
                          //   setState(() => _predictions = []);
                          // }
                        },
                        child: TextField(
                          focusNode: _searchFocusNode,
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Où allez-vous ?',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _isRouteVisible
                                ? IconButton(icon: const Icon(Icons.close),
                                onPressed: _cancelRoute)
                                : null,
                          ),
                          textInputAction: TextInputAction.search,
                          enableSuggestions: true,
                          autocorrect: true,)),
                  ),
                  // PLACES-DISABLED:
                  // if (_predictions.isNotEmpty)
                  //   Material(
                  //     elevation: 8,
                  //     borderRadius: BorderRadius.circular(15),
                  //     child: SizedBox(
                  //       height: 240,
                  //       child: ListView.builder(
                  //         shrinkWrap: true,
                  //         itemCount: _predictions.length,
                  //         itemBuilder: (context, index) {
                  //           final prediction = _predictions[index];
                  //           return ListTile(
                  //             title: Text(prediction.primaryText),
                  //             subtitle: Text(prediction.secondaryText),
                  //             onTap: () => _onPredictionTapped(prediction),
                  //           );
                  //         },
                  //       ),
                  //     ),
                  //   ),
                ],
              ),
            ),

            if (!_isRouteVisible)
              RouteOptionsPanel(
                onOptionsChanged: (options) {
                  _routeOptions = options;
                },
              ),

            if (_isRouteVisible && _tripDistance != null &&
                _tripDuration != null)
              TripInfoPanel(
                duration: _tripDuration!,
                distance: _tripDistance!,
                onCancel: _cancelRoute,
              ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'recenter_btn',
            onPressed: _goToCurrentPosition,
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'intercom_btn',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const IntercomScreen()),
              );
            },
            backgroundColor: Theme
                .of(context)
                .colorScheme
                .secondary,
            child: const Icon(Icons.podcasts),
          ),
        ],
      ),
    );
  }
}
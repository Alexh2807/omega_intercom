import 'dart:async';
import 'package.flutter/material.dart';
import 'package.google_maps_flutter/google_maps_flutter.dart';
import 'package.geolocator/geolocator.dart';
import 'package.http/http.dart' as http;
import 'dart:convert';

// N'OUBLIEZ PAS DE METTRE VOTRE CLÉ API GOOGLE MAPS ICI !
const String GOOGLE_MAPS_API_KEY = "VOTRE_CLE_API_GOOGLE_MAPS";

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  // Contrôleur pour interagir avec la GoogleMap
  final Completer<GoogleMapController> _controller = Completer();
  // Contrôleur pour le champ de recherche de destination
  final TextEditingController _searchController = TextEditingController();

  // Position initiale de la caméra (par défaut sur Paris)
  static const CameraPosition _kDefaultPosition = CameraPosition(
    target: LatLng(48.8566, 2.3522),
    zoom: 12,
  );

  // Ensemble des marqueurs sur la carte (position actuelle, destination)
  final Set<Marker> _markers = {};
  // Ensemble des polylignes (le tracé de l'itinéraire)
  final Set<Polyline> _polylines = {};
  // Position GPS actuelle de l'utilisateur
  LatLng? _currentPosition;
  // Style de la carte (sombre ou clair)
  String? _mapStyle;

  @override
  void initState() {
    super.initState();
    // Permet de détecter les changements de thème (clair/sombre) du système
    WidgetsBinding.instance.addObserver(this);
    // Charge le style de carte initial
    _loadMapStyle();
    // Démarre le processus de géolocalisation
    _determinePosition();
  }

  // Charge le bon style de carte (clair ou sombre) en fonction du thème de l'app
  Future<void> _loadMapStyle() async {
    final Brightness brightness = Theme.of(context).brightness;
    final String stylePath = brightness == Brightness.dark
        ? 'assets/map_styles/dark_mode.json'
        : 'assets/map_styles/light_mode.json';
    try {
      _mapStyle = await DefaultAssetBundle.of(context).loadString(stylePath);
    } catch (e) {
      // En cas d'erreur de chargement du style, on n'applique pas de style personnalisé
      _mapStyle = null;
    }
  }

  // Met à jour le style de la carte quand l'utilisateur change le thème de son téléphone
  @override
  void didChangePlatformBrightness() {
    setState(() {
      _loadMapStyle().then((_) async {
        final GoogleMapController controller = await _controller.future;
        controller.setMapStyle(_mapStyle);
      });
    });
  }

  // --- LOGIQUE DE GÉOLOCALISATION ---
  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Vérifie si le service de localisation est activé sur le téléphone
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showErrorDialog('Le service de localisation est désactivé.');
      return;
    }

    // Vérifie les permissions de l'application
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
          'La permission de localisation est refusée de manière permanente. Veuillez l\'activer dans les paramètres.');
      return;
    }

    // Récupère la position actuelle
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

    setState(() {
      // Met à jour la position actuelle
      _currentPosition = LatLng(position.latitude, position.longitude);
      // Efface les anciens marqueurs et ajoute le nouveau à la position actuelle
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

    // Centre la caméra sur la nouvelle position
    _goToCurrentPosition();
  }

  // Anime la caméra pour la déplacer vers la position actuelle de l'utilisateur
  Future<void> _goToCurrentPosition() async {
    if (_currentPosition == null) return;
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(
        target: _currentPosition!,
        zoom: 16.5,
        tilt: 30.0, // Donne un peu de perspective
      ),
    ));
  }

  // --- LOGIQUE DE CALCUL D'ITINÉRAIRE ---
  Future<void> _getDirections(String destination) async {
    if (_currentPosition == null || destination.isEmpty) return;

    // Construit l'URL pour appeler l'API Google Directions
    final String url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}&destination=$destination&key=$GOOGLE_MAPS_API_KEY';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['routes'].isNotEmpty) {
        // Récupère les points encodés de l'itinéraire
        final points = data['routes'][0]['overview_polyline']['points'];
        // Décode ces points en une liste de coordonnées géographiques
        final List<LatLng> polylineCoordinates = _decodePolyline(points);

        final LatLng destinationLatLng = LatLng(
            data['routes'][0]['legs'][0]['end_location']['lat'],
            data['routes'][0]['legs'][0]['end_location']['lng']
        );

        setState(() {
          // Efface l'ancien itinéraire
          _polylines.clear();
          // Ajoute le nouvel itinéraire sur la carte
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: polylineCoordinates,
              color: Colors.blueAccent,
              width: 6,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          );
          // Ajoute un marqueur pour la destination
          _markers.add(
            Marker(
              markerId: const MarkerId('destination'),
              position: destinationLatLng,
              infoWindow: InfoWindow(title: destination),
            ),
          );
        });
      } else {
        _showErrorDialog('Aucun itinéraire trouvé.');
      }
    } else {
      _showErrorDialog('Erreur lors du calcul de l\'itinéraire.');
    }
  }

  // Algorithme de Google pour décoder la chaîne de points de l'itinéraire
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

  // Affiche une boite de dialogue pour les erreurs
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erreur'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Nettoie l'observer pour éviter les fuites de mémoire
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  // --- CONSTRUCTION DE L'INTERFACE UTILISATEUR ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // La carte Google en arrière-plan
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _kDefaultPosition,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true, // Affiche le point bleu de localisation natif
            myLocationButtonEnabled: false, // On crée notre propre bouton
            zoomControlsEnabled: false, // On désactive les boutons de zoom par défaut
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
              // Applique le style de carte une fois qu'elle est prête
              controller.setMapStyle(_mapStyle);
            },
          ),
          // La barre de recherche
          Positioned(
            top: MediaQuery.of(context).padding.top + 15, // S'adapte à l'encoche du téléphone
            left: 15,
            right: 15,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Où allez-vous ?',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => _searchController.clear(),
                  ),
                ),
                onSubmitted: (value) {
                  _getDirections(value);
                  FocusScope.of(context).unfocus(); // Ferme le clavier
                },
              ),
            ),
          ),
        ],
      ),
      // Bouton flottant pour recentrer sur la position de l'utilisateur
      floatingActionButton: FloatingActionButton(
        onPressed: _goToCurrentPosition,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        child: const Icon(Icons.my_location),
      ),
    );
  }
}
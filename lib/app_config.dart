import 'dart:async';
import 'package:flutter/services.dart';

class AppConfig {
  static const MethodChannel _ch = MethodChannel('app.config');

  // Cached Google Map styles
  static String? lightMapStyle; // PERF: cached at startup
  static String? darkMapStyle;  // PERF: cached at startup

  // Cached API keys
  static String? placesKey;
  static String? directionsKey;

  static Future<void> init() async {
    // PERF: load styles once at startup
    try {
      lightMapStyle = await rootBundle.loadString('assets/map_styles/light_mode.json');
    } catch (_) {
      lightMapStyle = null;
    }
    try {
      darkMapStyle = await rootBundle.loadString('assets/map_styles/dark_mode.json');
    } catch (_) {
      darkMapStyle = null;
    }
    // Lazy-load keys on demand; no-op here.
  }

  static Future<String?> getMeta(String name) async {
    try {
      final v = await _ch.invokeMethod<String>('getMeta', {'name': name});
      return v;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getPlacesKey() async {
    if (placesKey != null) return placesKey;
    // Prefer custom meta, fallback to Google Maps common key
    placesKey = await getMeta('com.example.app.PLACES_KEY');
    placesKey ??= await getMeta('com.google.android.geo.API_KEY');
    return placesKey;
  }

  static Future<String?> getDirectionsKey() async {
    if (directionsKey != null) return directionsKey;
    // Prefer custom meta, fallback to Google Maps common key
    directionsKey = await getMeta('com.example.app.DIRECTIONS_KEY');
    directionsKey ??= await getMeta('com.google.android.geo.API_KEY');
    return directionsKey;
  }
}

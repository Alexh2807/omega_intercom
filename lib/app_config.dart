import 'dart:async';
import 'package:flutter/services.dart';

class AppConfig {
  static const MethodChannel _ch = MethodChannel('app.config');

  static String? lightMapStyle;
  static String? darkMapStyle;

  static Future<void> init() async {
    try {
      lightMapStyle = await rootBundle.loadString('assets/map_styles/light.json');
    } catch (_) {}
    try {
      darkMapStyle = await rootBundle.loadString('assets/map_styles/dark.json');
    } catch (_) {}
  }

  /// Read AndroidManifest meta-data or Info.plist value (when bridged natively).
  static Future<String?> getMeta(String key) async {
    try {
      final v = await _ch.invokeMethod<String>('getMeta', {'key': key});
      return v;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getPlacesKey() async {
    // Prefer a custom key, else fallback to common Google key
    return (await getMeta('com.example.app.PLACES_KEY')) ??
        (await getMeta('com.google.android.geo.API_KEY'));
  }

  static Future<String?> getDirectionsKey() async {
    return (await getMeta('com.example.app.DIRECTIONS_KEY')) ??
        (await getMeta('com.google.android.geo.API_KEY'));
  }
}
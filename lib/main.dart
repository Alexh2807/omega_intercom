import 'package:flutter/material.dart';
import 'package:omega_intercom/map_screen.dart'; // Notre futur écran principal

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Omega GPS',

      // Thème pour le mode clair
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1), // Un bleu foncé et élégant
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 2.0,
        ),
      ),

      // Thème pour le mode sombre
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1),
          brightness: Brightness.dark,
        ),
      ),

      themeMode: ThemeMode.system, // S'adapte au système de l'utilisateur
      home: const MapScreen(), // Lance l'écran de la carte
    );
  }
}
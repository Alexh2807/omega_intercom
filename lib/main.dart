import 'package:flutter/material.dart';
import 'package:omega_intercom/map_screen.dart';
import 'package:omega_intercom/app_config.dart';
import 'package:omega_intercom/widgets/debug_overlay.dart';
// Il n'est plus nécessaire d'importer le plugin Places ici

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Omega GPS',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            const DebugOverlay(),
          ],
        );
      },
      home: const MapScreen(),
    );
  }
}

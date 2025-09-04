import 'package:flutter/material.dart';
import 'package:omega_intercom/map_screen.dart';
import 'package:omega_intercom/app_config.dart';
import 'package:omega_intercom/widgets/debug_overlay.dart';

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
      title: 'OMEGA Intercom',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2196F3)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) {
        return Stack(children: [if (child != null) child, const DebugOverlay()]);
      },
      home: const MapScreen(),
    );
  }
}
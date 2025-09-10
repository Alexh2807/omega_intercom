import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer' as developer;
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'screens/gps_screen.dart';
import 'screens/intercom_page.dart';
import 'services/gps_state_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialiser Google Maps avec le dernier renderer pour éviter les logs Flogger
  await (GoogleMapsFlutterPlatform.instance as GoogleMapsFlutterAndroid)
      .initializeWithRenderer(AndroidMapRenderer.latest);

  // Configuration de l'interface système pour un look premium
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0A0A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  // Keep the screen on at all times while app is running
  await WakelockPlus.enable();

  runApp(const OmegaGpsApp());
}

class OmegaGpsApp extends StatelessWidget {
  const OmegaGpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OMEGA GPS + Intercom',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        primaryColor: const Color(0xFF00E676),
        cardColor: const Color(0xFF1E1E1E),
        dividerColor: const Color(0xFF333333),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: Color(0xFF00E676),
          unselectedItemColor: Color(0xFF666666),
          type: BottomNavigationBarType.fixed,
        ),
      ),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _navAnimationController;

  late List<Widget> _screens;

  final List<NavItem> _navItems = [
    NavItem(
      icon: Icons.map_rounded,
      activeIcon: Icons.map_rounded,
      label: 'Navigation',
      gradient: const LinearGradient(
        colors: [Color(0xFF2196F3), Color(0xFF21CBF3)],
      ),
    ),
    NavItem(
      icon: Icons.radio_rounded,
      activeIcon: Icons.radio_rounded,
      label: 'Intercom',
      gradient: const LinearGradient(
        colors: [Color(0xFF00E676), Color(0xFF00BCD4)],
      ),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _navAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    // Build screens with cross-toggle callbacks
    _screens = [
      GpsScreen(
        onSwitchToIntercom: () => setState(() => _selectedIndex = 1),
      ),
      IntercomPage(
        onSwitchToGPS: () => setState(() => _selectedIndex = 0),
      ),
    ];
    
    // Initialiser le service GPS dès le démarrage de l'application
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGlobalGPS();
    });
  }

  Future<void> _initializeGlobalGPS() async {
    try {
      final gpsService = GPSStateService();
      await gpsService.initialize();
      developer.log('✅ Service GPS simple initialisé', name: 'Main');
    } catch (e) {
      developer.log('❌ Erreur initialisation GPS simple: $e', name: 'Main');
    }
  }

  void _onItemTapped(int index) {
    if (index != _selectedIndex) {
      setState(() {
        _selectedIndex = index;
      });
      
      _navAnimationController.forward().then((_) {
        _navAnimationController.reverse();
      });
      
      // Vibration tactile premium
      HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _navAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0A0A),
              Color(0xFF1A1A1A),
              Color(0xFF0A0A0A),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: IndexedStack(
          index: _selectedIndex,
          children: _screens,
        ),
      ),
    );
  }
}

// Classe pour définir les éléments de navigation
class NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final LinearGradient gradient;

  NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.gradient,
  });
}

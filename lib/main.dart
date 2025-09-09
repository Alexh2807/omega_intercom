import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer' as developer;
import 'screens/gps_screen.dart';
import 'screens/intercom_page.dart';
import 'services/gps_state_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  final List<Widget> _screens = [
    const GpsScreen(),
    const IntercomPage(),
  ];

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
      
      // Navigation bottom premium avec glassmorphism
      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Row(
                children: List.generate(_navItems.length, (index) {
                  final isSelected = index == _selectedIndex;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _onItemTapped(index),
                      child: AnimatedBuilder(
                        animation: _navAnimationController,
                        builder: (context, child) {
                          return Container(
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: isSelected 
                                  ? LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        _navItems[index].gradient.colors.first.withValues(alpha: 0.15),
                                        _navItems[index].gradient.colors.last.withValues(alpha: 0.05),
                                      ],
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: EdgeInsets.all(isSelected ? 12 : 8),
                                  decoration: BoxDecoration(
                                    gradient: isSelected 
                                        ? _navItems[index].gradient
                                        : null,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: isSelected ? [
                                      BoxShadow(
                                        color: _navItems[index].gradient.colors.first.withValues(alpha: 0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ] : null,
                                  ),
                                  child: Icon(
                                    isSelected ? _navItems[index].activeIcon : _navItems[index].icon,
                                    color: isSelected ? Colors.white : const Color(0xFF666666),
                                    size: isSelected ? 24 : 20,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(
                                    fontSize: isSelected ? 11 : 10,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                    color: isSelected 
                                        ? _navItems[index].gradient.colors.first
                                        : const Color(0xFF666666),
                                    letterSpacing: 0.5,
                                  ),
                                  child: Text(_navItems[index].label),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
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

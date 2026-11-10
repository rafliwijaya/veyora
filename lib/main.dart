import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/breathing_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/measure_screen.dart';
import 'screens/splash_screen.dart';
import 'services/database_service.dart';
import 'services/stress_classifier.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    // Set orientasi portrait saja untuk kestabilan kamera & UX pada mobile
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } catch (_) {}

    // Inisialisasi database SQLite lokal
    try {
      await DatabaseService.instance.database;
    } catch (_) {}

    // Inisialisasi model biner Random Forest
    try {
      await StressClassifier.loadModel();
    } catch (_) {}
  }

  // Set status bar transparan dengan icon gelap
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const VeyoraApp());
}

class VeyoraApp extends StatelessWidget {
  const VeyoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Veyora',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}

class MainNavigationScaffold extends StatefulWidget {
  const MainNavigationScaffold({super.key});

  @override
  State<MainNavigationScaffold> createState() => _MainNavigationScaffoldState();
}

class _MainNavigationScaffoldState extends State<MainNavigationScaffold> {
  int _currentIndex = 0;

  void _onNavigateTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(onNavigateTab: _onNavigateTab),
      MeasureScreen(onNavigateTab: _onNavigateTab, isActive: _currentIndex == 1),
      BreathingScreen(onNavigateTab: _onNavigateTab),
      HistoryScreen(onNavigateTab: _onNavigateTab),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: AppColors.border.withValues(alpha: 0.6),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Beranda',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.favorite_border_rounded),
              activeIcon: Icon(Icons.favorite_rounded),
              label: 'Ukur',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.air_outlined),
              activeIcon: Icon(Icons.air_rounded),
              label: 'Napas',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.insights_outlined),
              activeIcon: Icon(Icons.insights_rounded),
              label: 'Riwayat',
            ),
          ],
        ),
      ),
    );
  }
}

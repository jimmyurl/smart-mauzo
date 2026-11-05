import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_mauzo/services/supabase_service.dart';
import 'auth_gate.dart';
import 'screens/scan_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supabaseService = SupabaseService();
  await supabaseService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Mauzo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1)),
        useMaterial3: true,
        // Change this one line to switch the font, e.g. GoogleFonts.interTextTheme()
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      // Login -> shop setup -> the app
      home: const AuthGate(home: MainScreen()),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const ScanScreen(),
    const SalesScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: Image.asset('assets/icons/scan.png', width: 24, height: 24),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            icon: Image.asset('assets/icons/sales.png', width: 24, height: 24),
            label: 'Sales',
          ),
          BottomNavigationBarItem(
            icon: Image.asset('assets/icons/profile.png', width: 24, height: 24),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
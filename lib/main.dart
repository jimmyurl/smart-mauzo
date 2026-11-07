import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth_gate.dart';
import 'screens/inventory_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/scan_screen.dart';
import 'services/supabase_service.dart';
import 'services/sync_service.dart';
import 'utils/login_required_view.dart';
import 'utils/require_login.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Show a clear message instead of cryptic network errors if the keys were never pasted in.
  if (!SupabaseService.isConfigured) {
    runApp(const SetupNeededApp());
    return;
  }
  await SupabaseService().initialize();
  await SyncService().init(); // offline sale queue + automatic sync
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

  // Home | Products | Sales | Profile
  final List<Widget> _screens = const [
    ScanScreen(),
    InventoryScreen(),
    SalesScreen(),
    ProfileScreen(),
  ];

  static const _titles = ['Home', 'Products', 'Sales', 'Profile'];

  /// Home is open to guests (browse-only). The other tabs need an account.
  Widget _body() {
    if (_currentIndex == 0 || isLoggedIn) return _screens[_currentIndex];
    return LoginRequiredView(title: _titles[_currentIndex]);
  }

  Widget _icon(String asset) => Image.asset(asset, width: 24, height: 24);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _body(),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedItemColor: Colors.blue[900],
        unselectedItemColor: Colors.grey[600],
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(icon: _icon('assets/icons/scan.png'), label: 'Home'),
          BottomNavigationBarItem(icon: _icon('assets/icons/products.png'), label: 'Products'),
          BottomNavigationBarItem(icon: _icon('assets/icons/sales.png'), label: 'Sales'),
          BottomNavigationBarItem(icon: _icon('assets/icons/profile.png'), label: 'Profile'),
        ],
      ),
    );
  }
}

/// Shown when SUPABASE_URL / SUPABASE_ANON_KEY in supabase_service.dart are still placeholders.
class SetupNeededApp extends StatelessWidget {
  const SetupNeededApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.settings_suggest, size: 56),
                  SizedBox(height: 16),
                  Text('Supabase is not set up yet',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Text(
                    'Open lib/services/supabase_service.dart and replace YOUR_SUPABASE_URL and '
                    'YOUR_SUPABASE_ANON_KEY with the values from your Supabase project '
                    '(Project Settings -> API).\n\nThen restart the app.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/shop_setup_screen.dart';
import 'services/shop_service.dart';

/// Decides what to show:
///   guest (no session)      -> the app in guest mode (login is requested
///                              only when they try to do something)
///   logged in, no shop      -> shop setup
///   logged in, has shop     -> the real app
class AuthGate extends StatefulWidget {
  final Widget home;
  const AuthGate({super.key, required this.home});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _svc = ShopService();
  StreamSubscription<AuthState>? _sub;
  Session? _session;
  Future<ShopInfo?>? _shop;

  @override
  void initState() {
    super.initState();
    _session = _svc.session;
    if (_session != null) _shop = _svc.myShop();
    _sub = _svc.authChanges.listen((state) {
      if (!mounted) return;
      final newId = state.session?.user.id;
      final changed = newId != _session?.user.id;
      setState(() {
        _session = state.session;
        // Only reload the shop when the user actually changes (not on hourly token refresh).
        if (changed) _shop = newId == null ? null : _svc.myShop();
      });
    });
  }

  void _reloadShop() => setState(() => _shop = _svc.myShop());

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Guest: let them look around. Screens call requireLogin() when an
    // action needs an account.
    if (_session == null) return widget.home;

    return FutureBuilder<ShopInfo?>(
      future: _shop,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, size: 48),
                  const SizedBox(height: 16),
                  const Text('Could not reach the server.\nCheck your internet connection.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _reloadShop, child: const Text('Try again')),
                  TextButton(onPressed: _svc.signOut, child: const Text('Sign out')),
                ],
              ),
            ),
          );
        }
        if (snap.data == null) return ShopSetupScreen(onDone: _reloadShop);
        return widget.home;
      },
    );
  }
}
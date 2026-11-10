import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/shop_setup_screen.dart';
import 'services/offline_store.dart';
import 'services/shop_service.dart';
import 'widgets/recovery_nudge.dart';

enum _ShopState { has, none }

/// Decides what to show:
///   guest (no session)      -> the app in guest mode (login is requested
///                              only when they try to do something)
///   logged in, no shop      -> shop setup
///   logged in, has shop     -> the real app
///
/// Works without internet: if the server cannot be reached, a user who already
/// had a shop the last time they were online goes straight into the app.
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
  Future<_ShopState>? _shop;

  /// The user whose shop we last asked about. (Do not compare with [_userId]:
  /// another listener may already have updated it when this one runs, which left
  /// the screen waiting for a shop check that never started.)
  String? _loadedFor;

  /// Signed in on this phone: a live session, or the user remembered from the
  /// last online sign-in (when the app was started without internet).
  String? get _userId => _session?.user.id ?? OfflineIdentity.userId;

  @override
  void initState() {
    super.initState();
    _session = _svc.session;
    ShopService.shopChanged.addListener(_onShopChanged);
    _loadedFor = _userId;
    if (_userId != null) _shop = _loadShop();
    _sub = _svc.authChanges.listen(
      (state) {
        if (!mounted) return;
        OfflineIdentity.onAuth(state);
        final uid = state.session?.user.id;
        setState(() {
          _session = state.session;
          if (state.event == AuthChangeEvent.signedOut) {
            _loadedFor = null;
            _shop = null;
          } else if (uid != null && uid != _loadedFor) {
            // A different person signed in (not an hourly token refresh, and not a
            // remembered login being restored): check their shop.
            _loadedFor = uid;
            _shop = _loadShop();
          }
        });
      },
      onError: (Object e) => debugPrint('Auth event error: $e'),
    );
  }

  /// Asks the server whether this user has a shop. If the server cannot be
  /// reached (or answers too slowly), trust what this phone remembers.
  Future<_ShopState> _loadShop() async {
    final uid = _userId;
    try {
      if (_svc.session == null) throw StateError('no live session yet');
      final shop = await _svc.myShop().timeout(const Duration(seconds: 6));
      if (uid != null) await OfflineIdentity.setHasShop(uid, shop != null);
      return shop == null ? _ShopState.none : _ShopState.has;
    } catch (e) {
      if (uid != null && OfflineIdentity.hasShop(uid)) return _ShopState.has;
      rethrow;
    }
  }

  void _reloadShop() => setState(() => _shop = _loadShop());

  void _onShopChanged() {
    if (mounted && _userId != null) _reloadShop();
  }

  @override
  void dispose() {
    ShopService.shopChanged.removeListener(_onShopChanged);
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Guest: let them look around. Screens call requireLogin() when an
    // action needs an account.
    if (_userId == null) return widget.home;

    // Safety net: never wait on a check that was never started.
    _shop ??= _loadShop();

    return FutureBuilder<_ShopState>(
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
        if (snap.data == _ShopState.none) return ShopSetupScreen(onDone: _reloadShop);
        return RecoveryNudge(child: widget.home);
      },
    );
  }
}
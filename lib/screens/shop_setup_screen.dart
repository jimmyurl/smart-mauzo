import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/shop_service.dart';
import '../services/signup_intent.dart';

/// Shown once after sign-up: create your shop (you become the owner) or join one with a code (you become a cashier).
class ShopSetupScreen extends StatefulWidget {
  final VoidCallback onDone;
  const ShopSetupScreen({super.key, required this.onDone});

  @override
  State<ShopSetupScreen> createState() => _ShopSetupScreenState();
}

class _ShopSetupScreenState extends State<ShopSetupScreen> {
  final _svc = ShopService();
  final _name = TextEditingController();
  bool _busy = false;
  bool _ready = false; // the cashier flag has been read from the phone

  /// This account logs in with a cashier code: it can never create a shop.
  bool get _isCashier =>
      SignupIntent.isCashier(Supabase.instance.client.auth.currentUser?.id);

  @override
  void initState() {
    super.initState();
    SignupIntent.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      widget.onDone();
    } on PostgrestException catch (e) {
      _msg(e.message);
    } catch (_) {
      _msg('Something went wrong. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  /// A cashier whose code was removed (or never worked) lands here.
  Widget _noAccess(Color blue) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Mauzo'),
        backgroundColor: blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: Colors.grey[600]),
              const SizedBox(height: 16),
              const Text('You do not have access to a shop',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Ask your shop owner for a new cashier code, then log in again.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _svc.signOut,
                style: ElevatedButton.styleFrom(
                    backgroundColor: blue, foregroundColor: Colors.white),
                child: const Text('Log in with a new code'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blue = Colors.blue[900]!;
    if (!_ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_isCashier) return _noAccess(blue);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your shop'),
        backgroundColor: blue,
        foregroundColor: Colors.white,
        actions: [TextButton(onPressed: _svc.signOut, child: const Text('Sign out', style: TextStyle(color: Colors.white)))],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('I own a shop',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Create your shop. You can add cashiers later; each one gets their own login code.',
                        style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Shop name', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _run(() => _svc.createShop(_name.text)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: blue, foregroundColor: Colors.white),
                        child: const Text('Create shop'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Are you a cashier? Tap Sign out, then choose "Cashier" on the login page '
              'and enter the code your shop owner gave you.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }
}
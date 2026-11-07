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
  final _code = TextEditingController();
  bool _busy = false;
  bool _ready = false; // cashier flag read from the phone

  /// This account signed up as a cashier: it may only join a shop, never create one.
  bool get _cashierOnly =>
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
    _code.dispose();
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

  @override
  Widget build(BuildContext context) {
    final blue = Colors.blue[900]!;
    return Scaffold(
      appBar: AppBar(
        title: Text(_ready && _cashierOnly ? 'Join your shop' : 'Set up your shop'),
        backgroundColor: blue,
        foregroundColor: Colors.white,
        actions: [TextButton(onPressed: _svc.signOut, child: const Text('Sign out', style: TextStyle(color: Colors.white)))],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_cashierOnly) Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('I own a shop',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Create your shop. You can add cashiers later with a code.',
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
            if (!_cashierOnly) const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('I work in a shop',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Ask the owner for the shop code (shown on their Profile tab).',
                        style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          labelText: 'Shop code', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _run(() => _svc.joinShop(_code.text)),
                        child: const Text('Join shop'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }
}
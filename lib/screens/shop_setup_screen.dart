import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/shop_service.dart';

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
            const SizedBox(height: 16),
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
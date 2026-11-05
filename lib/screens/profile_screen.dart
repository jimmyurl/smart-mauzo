import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/shop_service.dart';

/// Account + shop details, shop code for adding cashiers (owners only), and sign out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _svc = ShopService();
  late Future<ShopInfo?> _shop;

  @override
  void initState() {
    super.initState();
    _shop = _svc.myShop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<ShopInfo?>(
        future: _shop,
        builder: (context, snap) {
          final shop = snap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(_svc.email ?? ''),
                  subtitle: Text(shop == null ? '' : (shop.isOwner ? 'Owner' : 'Cashier')),
                ),
              ),
              if (snap.connectionState != ConnectionState.done)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else if (shop != null) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.storefront),
                    title: Text(shop.name),
                    subtitle: const Text('Your shop'),
                  ),
                ),
                if (shop.isOwner && shop.joinCode != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.group_add),
                      title: Text(shop.joinCode!,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2)),
                      subtitle: const Text('Shop code: give this to cashiers so they can join'),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: shop.joinCode!));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Shop code copied')));
                        },
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _svc.signOut, // AuthGate returns to the login screen
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          );
        },
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/shop_service.dart';
import '../utils/money.dart';
import '../utils/require_login.dart';
import '../services/app_language.dart';
import '../widgets/language_switch.dart';

/// Profile tab.
///  - Guest: explains what an account gives you and offers Log in / Sign up.
///  - Logged in: who you are, your shop, the shop code (owners), and sign out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _svc = ShopService();
  Future<ShopInfo?>? _shop;
  bool _fromCache = false; // showing details saved on this phone

  @override
  void initState() {
    super.initState();
    // Guests have no shop, so only load it when logged in.
    if (isLoggedIn) _shop = _loadShop();
  }

  /// The shop from the server, or (with no connection) the copy saved on the phone.
  Future<ShopInfo?> _loadShop() async {
    final r = await _svc.myShopOrCached();
    if (mounted && r.fromCache != _fromCache) setState(() => _fromCache = r.fromCache);
    return r.shop;
  }

  Future<void> _reload() async {
    final future = _loadShop();
    setState(() => _shop = future);
    try {
      await future;
    } catch (_) {
      // The error is shown by the FutureBuilder.
    }
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sign out?')),
        content: Text(tr('You will need to log in again to make sales.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sign out'))),
        ],
      ),
    );
    if (ok == true) {
      await _svc.signOut(); // AuthGate switches back to guest mode
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final guest = !isLoggedIn;

    return Scaffold(
      backgroundColor: Colors.blue[900],
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            guest ? _guestHeader() : _userHeader(),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: guest ? _guestBody() : _userBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Headers (blue area at the top)
  // ---------------------------------------------------------------------------

  Widget _guestHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.blue[700],
            child: const Icon(Icons.person_outline, size: 38, color: Colors.white),
          ),
          const SizedBox(height: 14),
          Text(tr('Guest'),
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(tr('You are not logged in'),
              style: TextStyle(color: Colors.blue[100], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _userHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: FutureBuilder<ShopInfo?>(
        future: _shop,
        builder: (context, snap) {
          final shop = snap.data;
          return Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.white,
                child: Icon(shop != null && !shop.isOwner ? Icons.badge_outlined : Icons.storefront,
                    size: 34, color: Colors.blue[900]),
              ),
              if (shop != null) ...[
                const SizedBox(height: 14),
                Text(shop.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    shop.isOwner ? tr('Shop owner') : tr('Cashier'),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Guest body
  // ---------------------------------------------------------------------------

  Widget _guestBody() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(tr('Create a free account to:'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _benefit(Icons.shopping_cart, 'Make and record sales'),
        _benefit(Icons.inventory, 'Manage your products and stock'),
        _benefit(Icons.assessment, 'See reports of how your shop is doing'),
        _benefit(Icons.group_add, 'Add cashiers to your shop'),
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: () => requireLogin(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[900],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(tr('Log in or Sign up'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => requireLogin(context, asCashier: true),
          icon: const Icon(Icons.badge_outlined),
          label: const Text("I'm a cashier: log in with my code"),
        ),
      ],
    );
  }

  Widget _benefit(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.blue[900], size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Logged-in body
  // ---------------------------------------------------------------------------

  Widget _userBody() {
    return FutureBuilder<ShopInfo?>(
      future: _shop,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, size: 40),
                  const SizedBox(height: 12),
                  Text(tr('Could not load your shop.\nCheck your internet connection.'),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _reload, child: Text(tr('Try again'))),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _confirmSignOut, child: Text(tr('Sign out'))),
                ],
              ),
            ),
          );
        }

        final shop = snap.data;

        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              if (_fromCache)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off, size: 18, color: Colors.orange[900]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No internet. Showing the details saved on this phone. Pull down to refresh.',
                          style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                        ),
                      ),
                    ],
                  ),
                ),
              if (shop != null) ...[
                _sectionTitle('My shop'),
                _infoCard(
                  icon: Icons.storefront,
                  title: shop.name,
                  subtitle: shop.isOwner ? 'You own this shop' : 'You work here as a cashier',
                ),
                if (shop.isOwner) ...[
                  const SizedBox(height: 24),
                  _sectionTitle('My cashiers'),
                  if (_fromCache)
                    _infoCard(
                      icon: Icons.wifi_off,
                      title: 'Cashier list needs internet',
                      subtitle: 'Connect to see and manage your cashiers.',
                    )
                  else
                    const _TeamSection(),
                ],
                if (!shop.isOwner) ...[
                  const SizedBox(height: 12),
                  _infoCard(
                    icon: Icons.lock_outline,
                    title: tr('Your sales only'),
                    subtitle: tr('You can make sales and see the sales you made.'),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              _sectionTitle('Language'),
              const LanguageSwitch(),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _confirmSignOut,
                  icon: const Icon(Icons.logout),
                  label: Text(tr('Sign out')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[700],
                    side: BorderSide(color: Colors.red[200]!),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(tr(text),
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
              letterSpacing: 0.5)),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.blue[900]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Owner only: add cashiers (each gets a personal login code), see what each has
/// sold, show a cashier's code again, or remove a cashier.
class _TeamSection extends StatefulWidget {
  const _TeamSection();

  @override
  State<_TeamSection> createState() => _TeamSectionState();
}

class _TeamSectionState extends State<_TeamSection> {
  final _svc = ShopService();
  late Future<List<TeamMember>> _future = _svc.team();

  void _reload() => setState(() => _future = _svc.team());

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add() async {
    // Created here, not inside the dialog, so the typed name survives the keyboard
    // opening and closing.
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(tr('Add a cashier')),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: "Cashier's name",
              hintText: 'e.g. Asha',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: Text(tr('Create code'))),
          ],
        );
      },
    );
    c.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final code = await _svc.addCashier(name);
      if (!mounted) return;
      _reload();
      await _showCode(name, '${code.substring(0, 4)}-${code.substring(4)}');
    } on PostgrestException catch (e) {
      _snack(friendly(e));
    } catch (_) {
      // The reply may have been lost after the server saved it: show the list again.
      if (mounted) _reload();
      _snack('The connection is weak, so we could not confirm. Look at the list '
          'below: if $name is there, tap the key icon to see the code; if not, try again.');
    }
  }

  Future<void> _showCode(String name, String pretty) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("$name's login code"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(pretty,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: Colors.blue[900])),
            ),
            const SizedBox(height: 12),
            Text(
              'Give this code to $name only. On the login page they choose "Cashier" '
              'and type the code. No phone number or password is needed.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: pretty));
              Navigator.pop(ctx);
              _snack(tr('Code copied'));
            },
            child: Text(tr('Copy')),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Done'))),
        ],
      ),
    );
  }

  Future<void> _remove(TeamMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${m.label}?'),
        content: const Text(
            'Their code stops working and they lose access straight away. '
            'Their past sales stay in your records.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Remove'), style: TextStyle(color: Colors.red[700])),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (m.code != null) {
        await _svc.removeCashier(m.code!);
      } else if (m.userId != null) {
        await _svc.removeMember(m.userId!); // older phone-number cashier
      }
      if (!mounted) return;
      _reload();
      _snack('${m.label} removed');
    } catch (_) {
      _snack(tr('Could not remove. Check your internet and try again.'));
    }
  }

  String _status(TeamMember m) {
    if (!m.claimed) return 'Not logged in yet';
    if (m.salesCount == 0) return 'No sales yet';
    return '${m.salesCount} sale${m.salesCount == 1 ? '' : 's'}  •  ${tzs(m.salesTotal)}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TeamMember>>(
      future: _future,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final cashiers = [
          for (final m in (snap.data ?? const <TeamMember>[])) if (!m.isOwner) m
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snap.hasError)
              Row(
                children: [
                  Expanded(
                    child: Text(tr('Could not load your cashiers.'),
                        style: TextStyle(color: Colors.grey[700])),
                  ),
                  TextButton(onPressed: _reload, child: Text(tr('Try again'))),
                ],
              )
            else if (cashiers.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'No cashiers yet. Add one: they get their own code and see only the '
                  'sales they make themselves.',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              )
            else
              for (final m in cashiers)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.label,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(_status(m),
                                style: TextStyle(color: Colors.grey[800], fontSize: 13)),
                            Text(
                              m.lastSale != null
                                  ? 'Last sale ${DateFormat('d MMM, HH:mm').format(m.lastSale!.toLocal())}'
                                  : 'Added ${DateFormat('d MMM yyyy').format(m.joinedAt.toLocal())}',
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (m.prettyCode != null)
                        IconButton(
                          onPressed: () => _showCode(m.label, m.prettyCode!),
                          icon: Icon(Icons.vpn_key_outlined, color: Colors.blue[900]),
                          tooltip: tr('Show login code'),
                        ),
                      IconButton(
                        onPressed: () => _remove(m),
                        icon: Icon(Icons.person_remove_outlined, color: Colors.red[700]),
                        tooltip: tr('Remove cashier'),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: loading ? null : _add,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(tr('Add a cashier')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );
      },
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/shop_service.dart';
import '../utils/money.dart';
import '../utils/require_login.dart';

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

  @override
  void initState() {
    super.initState();
    // Guests have no shop, so only load it when logged in.
    if (isLoggedIn) _shop = _svc.myShop();
  }

  Future<void> _reload() async {
    final future = _svc.myShop();
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
        title: const Text('Sign out?'),
        content: const Text('You will need to log in again to make sales.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) {
      await _svc.signOut(); // AuthGate switches back to guest mode
    }
  }

  /// Owner: replace the shop code. The old code stops working at once.
  Future<void> _confirmNewCode() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Make a new shop code?'),
        content: const Text(
            'The old code will stop working. Cashiers who already joined are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Make new code')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.newJoinCode();
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('New shop code ready')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not make a new code. Check your internet.')));
    }
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shop code copied')),
    );
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
          const Text('Guest',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('You are not logged in',
              style: TextStyle(color: Colors.blue[100], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _userHeader() {
    final email = _svc.email ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

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
                child: Text(initial,
                    style: TextStyle(
                        fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue[900])),
              ),
              const SizedBox(height: 14),
              Text(email,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              if (shop != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    shop.isOwner ? 'Shop owner' : 'Cashier',
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
        const Text('Create a free account to:',
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
            child: const Text('Log in or Sign up',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
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
                  const Text('Could not load your shop.\nCheck your internet connection.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _reload, child: const Text('Try again')),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _confirmSignOut, child: const Text('Sign out')),
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
              if (shop != null) ...[
                _sectionTitle('My shop'),
                _infoCard(
                  icon: Icons.storefront,
                  title: shop.name,
                  subtitle: shop.isOwner ? 'You own this shop' : 'You work here as a cashier',
                ),
                if (shop.isOwner && shop.joinCode != null) ...[
                  const SizedBox(height: 24),
                  _sectionTitle('Add a cashier'),
                  _shopCodeCard(shop.joinCode!),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _confirmNewCode,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Make a new code'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle('My cashiers'),
                  _TeamSection(svc: _svc, onNewCode: _confirmNewCode),
                ],
                if (!shop.isOwner) ...[
                  const SizedBox(height: 12),
                  _infoCard(
                    icon: Icons.lock_outline,
                    title: 'Your sales only',
                    subtitle: 'You can make sales and see the sales you made.',
                  ),
                ],
              ],
              const SizedBox(height: 24),
              _sectionTitle('Account'),
              _infoCard(
                icon: Icons.email_outlined,
                title: _svc.email ?? '',
                subtitle: 'Logged in with this email',
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _confirmSignOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
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
      child: Text(text,
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

  Widget _shopCodeCard(String code) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Give this code to your cashier. When they sign up they choose "I\'m a cashier" and type it in, and they join your shop straight away.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    code,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: Colors.blue[900],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: () => _copyCode(code),
                style: IconButton.styleFrom(backgroundColor: Colors.blue[900]),
                icon: const Icon(Icons.copy, color: Colors.white),
                tooltip: 'Copy code',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Owner only: the cashiers in the shop, what each has sold, and a way to remove one.
class _TeamSection extends StatefulWidget {
  final ShopService svc;
  final VoidCallback onNewCode;
  const _TeamSection({required this.svc, required this.onNewCode});

  @override
  State<_TeamSection> createState() => _TeamSectionState();
}

class _TeamSectionState extends State<_TeamSection> {
  late Future<List<TeamMember>> _future = widget.svc.team();

  void _reload() => setState(() => _future = widget.svc.team());

  Future<void> _remove(TeamMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${m.label}?'),
        content: const Text(
            'They lose access to your shop straight away. Their past sales stay in your records.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: TextStyle(color: Colors.red[700])),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.svc.removeMember(m.userId);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${m.label} removed'),
        duration: const Duration(seconds: 8),
        // They still know the old code, so offer a fresh one right away.
        action: SnackBarAction(label: 'New shop code', onPressed: widget.onNewCode),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove. Check your internet and try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TeamMember>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Row(
            children: [
              Expanded(
                child: Text('Could not load your cashiers.',
                    style: TextStyle(color: Colors.grey[700])),
              ),
              TextButton(onPressed: _reload, child: const Text('Try again')),
            ],
          );
        }
        final cashiers = [for (final m in snap.data!) if (!m.isOwner) m];
        if (cashiers.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'No cashiers yet. Give them the shop code above. Each cashier sees only '
              'the sales they make themselves.',
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
          );
        }
        return Column(
          children: [
            for (final m in cashiers)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
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
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(
                            m.salesCount == 0
                                ? 'No sales yet'
                                : '${m.salesCount} sale${m.salesCount == 1 ? '' : 's'}  •  ${tzs(m.salesTotal)}',
                            style: TextStyle(color: Colors.grey[800], fontSize: 13),
                          ),
                          Text(
                            m.lastSale == null
                                ? 'Joined ${DateFormat('d MMM yyyy').format(m.joinedAt.toLocal())}'
                                : 'Last sale ${DateFormat('d MMM, HH:mm').format(m.lastSale!.toLocal())}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _remove(m),
                      icon: Icon(Icons.person_remove_outlined, color: Colors.red[700]),
                      tooltip: 'Remove cashier',
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
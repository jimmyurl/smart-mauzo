import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/sale.dart';
import '../services/supabase_service.dart';
import '../utils/money.dart';
import '../utils/require_login.dart';
import 'inventory_screen.dart';
import 'new_sale_screen.dart';
import 'report_screen.dart';

class MobileScannerPage extends StatelessWidget {
  const MobileScannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Barcode')),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final String code = barcodes.first.rawValue ?? '';
            Navigator.of(context).pop(code);
          }
        },
      ),
    );
  }
}

/// Home tab.
///  - Logged in: real numbers from the shop's sales (today's total, orders,
///    items sold, change vs yesterday) and the 5 most recent sales.
///  - Guest: clearly-labelled sample data, with prompts to log in.
class ScanScreen extends StatefulWidget {
  const ScanScreen({Key? key}) : super(key: key);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  static const _cashColor = Color(0xFF2E7D32);
  static const _mobileColor = Color(0xFF1565C0);

  final SupabaseService _supabaseService = SupabaseService();

  List<Sale> _sales = [];
  bool _isLoading = false;
  String _errorMessage = '';

  bool get _guest => !isLoggedIn;

  @override
  void initState() {
    super.initState();
    // Guests have no shop (and RLS would return nothing), so only fetch when logged in.
    if (!_guest) {
      _isLoading = true;
      _fetchSales();
    }
  }

  Future<void> _fetchSales() async {
    try {
      final sales = await _supabaseService.fetchSales();
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _errorMessage = '';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '$e';
        _isLoading = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    _fetchSales();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _openNewSale() async {
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NewSaleScreen()),
    );
    // Show the sale that was just made.
    if (mounted && isLoggedIn) _fetchSales();
  }

  /// Opens [screen] only if the user is logged in; guests get the login prompt.
  Future<void> _openGuarded(Widget screen) async {
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  // ---------------------------------------------------------------------------
  // Numbers (all calculated from the real sales list)
  // ---------------------------------------------------------------------------

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  List<Sale> get _todaySales {
    final start = _startOfDay(DateTime.now());
    return _sales.where((s) => !s.timestamp.toLocal().isBefore(start)).toList();
  }

  List<Sale> get _yesterdaySales {
    final today = _startOfDay(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    return _sales.where((s) {
      final t = s.timestamp.toLocal();
      return !t.isBefore(yesterday) && t.isBefore(today);
    }).toList();
  }

  double _revenue(List<Sale> sales) => sales.fold<double>(0, (sum, s) => sum + s.total);

  /// "+12%" / "-5%" compared with yesterday, or "-" when there is nothing to compare.
  String _changeVsYesterday(double today, double yesterday) {
    if (yesterday <= 0) return '-';
    final pct = ((today - yesterday) / yesterday * 100).round();
    return pct > 0 ? '+$pct%' : '$pct%';
  }

  String _timeAgo(DateTime time) {
    final local = time.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m min${m == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hr${h == 1 ? '' : 's'} ago';
    }
    if (_startOfDay(DateTime.now()).difference(_startOfDay(local)).inDays == 1) {
      return 'Yesterday';
    }
    return DateFormat('d MMM').format(local);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final guest = _guest;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue[900]!,
              Colors.blue[800]!,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(guest),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 30),
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: guest
                      ? SingleChildScrollView(child: _guestContent())
                      : RefreshIndicator(
                          onRefresh: _fetchSales,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: _userContent(),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewSale,
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('New Sale'),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Content
  // ---------------------------------------------------------------------------

  Widget _guestContent() {
    return Column(
      children: [
        _buildGuestBanner(),
        _buildSummaryCard(
          amount: 'TZS 2,850,000',
          orders: '23',
          items: '45',
          change: '+15%',
          sample: true,
        ),
        _buildQuickActions(),
        _buildRecentHeader(sample: true),
        _sampleTransactions(),
        const SizedBox(height: 90),
      ],
    );
  }

  Widget _userContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 120),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 60),
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(_errorMessage, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _retry, child: const Text('Retry')),
          ],
        ),
      );
    }

    final today = _todaySales;
    final todayRevenue = _revenue(today);
    final yesterdayRevenue = _revenue(_yesterdaySales);
    final itemsSold = today.fold<int>(0, (sum, s) => sum + s.quantity);

    return Column(
      children: [
        _buildSummaryCard(
          amount: tzs(todayRevenue),
          orders: '${today.length}',
          items: '$itemsSold',
          change: _changeVsYesterday(todayRevenue, yesterdayRevenue),
          sample: false,
        ),
        _buildQuickActions(),
        _buildRecentHeader(sample: false),
        _recentTransactions(),
        const SizedBox(height: 90),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Pieces
  // ---------------------------------------------------------------------------

  Widget _buildAppBar(bool guest) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SmartMAUZO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                guest ? 'Welcome, guest!' : 'Welcome back!',
                style: TextStyle(
                  color: Colors.blue[100],
                  fontSize: 16,
                ),
              ),
            ],
          ),
          // Guests: tapping the avatar opens login/signup.
          GestureDetector(
            onTap: guest ? () => requireLogin(context) : null,
            child: CircleAvatar(
              backgroundColor: Colors.blue[700],
              child: Icon(
                guest ? Icons.login : Icons.person,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blue[100]!),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue[900]),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'You are browsing as a guest. Log in to make sales and see your real numbers.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => requireLogin(context),
              child: const Text('Log in'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String amount,
    required String orders,
    required String items,
    required String change,
    required bool sample,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple[400]!, Colors.purple[600]!],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Today\'s Sales',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (sample) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Sample data',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                amount,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSalesStat('Orders', orders),
                _buildSalesStat('Items Sold', items),
                _buildSalesStat('vs Yesterday', change),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _openNewSale,
                child: _buildActionButton(
                  icon: Icons.shopping_cart,
                  label: 'New Sale',
                  color: Colors.blue,
                ),
              ),
              GestureDetector(
                onTap: () => _openGuarded(const InventoryScreen()),
                child: _buildActionButton(
                  icon: Icons.inventory,
                  label: 'Inventory',
                  color: Colors.green,
                ),
              ),
              GestureDetector(
                onTap: () => _openGuarded(const ReportsScreen()),
                child: _buildActionButton(
                  icon: Icons.assessment,
                  label: 'Reports',
                  color: Colors.orange,
                ),
              ),
              GestureDetector(
                onTap: () async {
                  if (!await requireLogin(context)) return;
                  // TODO: open the settings screen once it exists.
                },
                child: _buildActionButton(
                  icon: Icons.settings,
                  label: 'Settings',
                  color: Colors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            icon,
            color: color,
            size: 30,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentHeader({required bool sample}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        children: [
          const Text(
            'Recent Transactions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (sample) ...[
            const SizedBox(width: 10),
            Text('Sample', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ],
      ),
    );
  }

  /// The 5 newest real sales (fetchSales returns newest first).
  Widget _recentTransactions() {
    if (_sales.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          children: [
            Icon(Icons.receipt_long, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No sales yet.\nTap "New Sale" to make your first one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: _sales.take(5).map((sale) {
          return _transactionTile(
            icon: sale.isMobile ? Icons.smartphone : Icons.payments,
            iconColor: sale.isMobile ? _mobileColor : _cashColor,
            title: sale.productTitle,
            subtitle:
                '${sale.quantity} item${sale.quantity == 1 ? '' : 's'}  •  ${sale.isMobile ? 'Mobile/Card' : 'Cash'}',
            amount: tzs(sale.total),
            time: _timeAgo(sale.timestamp),
          );
        }).toList(),
      ),
    );
  }

  Widget _sampleTransactions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _transactionTile(
            icon: Icons.payments,
            iconColor: _cashColor,
            title: 'Sample product',
            subtitle: '2 items  •  Cash',
            amount: 'TZS 105,000',
            time: '2 mins ago',
          ),
          _transactionTile(
            icon: Icons.smartphone,
            iconColor: _mobileColor,
            title: 'Sample product',
            subtitle: '1 item  •  Mobile/Card',
            amount: 'TZS 45,000',
            time: '1 hr ago',
          ),
          _transactionTile(
            icon: Icons.payments,
            iconColor: _cashColor,
            title: 'Sample product',
            subtitle: '3 items  •  Cash',
            amount: 'TZS 78,000',
            time: '3 hrs ago',
          ),
        ],
      ),
    );
  }

  Widget _transactionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String amount,
    required String time,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                time,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
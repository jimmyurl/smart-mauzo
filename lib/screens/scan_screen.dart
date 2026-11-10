import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../services/offline_store.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../utils/money.dart';
import '../utils/payment_style.dart';
import '../utils/require_login.dart';
import '../widgets/offline_data_banner.dart';
import 'credit_screen.dart';
import 'daily_summary_screen.dart';
import 'expenses_screen.dart';
import 'inventory_screen.dart';
import 'new_sale_screen.dart';
import 'report_screen.dart';
import 'sales_screen.dart';
import '../services/app_language.dart';

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
  List<Product> _products = [];
  bool _fromCache = false; // showing the copy saved on this phone
  DateTime? _savedAt;
  int _tab = 0; // 0 = Recent sales, 1 = Low stock
  bool _hideAmount = false;
  static const int _lowStock = 5;
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
      final load = await _supabaseService.fetchSalesOrCached();
      List<Product> products = _products;
      try {
        final p = await _supabaseService.getProductsOrCached();
        products = SyncService().applyPending(p.products);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _sales = load.sales;
        _fromCache = load.fromCache;
        _savedAt = load.savedAt;
        _products = products;
        _errorMessage = '';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = friendly(e);
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
              if (!guest && _fromCache) OfflineDataBanner(savedAt: _savedAt),
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
        label: Text(tr('New Sale')),
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
        _buildTabs(sample: true),
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
            ElevatedButton(onPressed: _retry, child: Text(tr('Retry'))),
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
          orders: '${Order.group(today).length}',
          items: '$itemsSold',
          change: _changeVsYesterday(todayRevenue, yesterdayRevenue),
          sample: false,
        ),
        _buildQuickActions(),
        _buildTabs(sample: false),
        if (_tab == 0) _recentTransactions() else _lowStockList(),
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
                guest ? tr('Welcome, guest!') : tr('Welcome back!'),
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
              child: Text(tr('Log in')),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF4FC3F7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text("Today's sales",
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                if (sample) ...[
                  const SizedBox(width: 8),
                  _pill('Sample'),
                ],
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _hideAmount = !_hideAmount),
                  child: Icon(
                    _hideAmount ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _hideAmount ? 'TZS ••••••' : amount,
                style: const TextStyle(
                    color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _pill('$orders orders'),
                      _pill('$items items'),
                      _pill('$change vs yesterday'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _openGuarded(const SalesScreen()),
                  child: const CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.arrow_forward,
                        size: 18, color: Color(0xFF1565C0)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
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
    final actions = <Widget>[
      _action(Icons.shopping_cart_outlined, 'New sale', _openNewSale),
      _action(Icons.inventory_2_outlined, 'Products',
          () => _openGuarded(const InventoryScreen())),
      _action(Icons.calendar_month_outlined, 'Sales',
          () => _openGuarded(const SalesScreen())),
      _action(Icons.assessment_outlined, 'Reports',
          () => _openGuarded(const ReportsScreen())),
      _action(Icons.today_outlined, 'Daily',
          () => _openGuarded(const DailySummaryScreen())),
      if (OfflineIdentity.isOwner)
        _action(Icons.menu_book_outlined, 'Credit',
            () => _openGuarded(const CreditScreen())),
      if (OfflineIdentity.isOwner)
        _action(Icons.payments_outlined, 'Expenses',
            () => _openGuarded(const ExpensesScreen())),
    ];
    // Seven buttons are too narrow for one row on a phone: owners get two rows.
    final perRow = actions.length > 6 ? 4 : actions.length;
    final rows = <List<Widget>>[
      for (var i = 0; i < actions.length; i += perRow)
        actions.sublist(i, i + perRow > actions.length ? actions.length : i + perRow),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            for (var r = 0; r < rows.length; r++)
              Padding(
                padding: EdgeInsets.only(top: r == 0 ? 0 : 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ...rows[r],
                    // keep the buttons of a shorter last row the same width as the rest
                    for (var i = rows[r].length; i < perRow; i++)
                      const Expanded(child: SizedBox()),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    // Expanded: every button gets an equal share of the row, so the row always
    // fits the screen however many buttons there are.
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 26, color: Colors.blue[900]),
              const SizedBox(height: 6),
              Text(tr(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  /// "Recent | Low stock" tabs, like the Tokens / NFT / DeFi row in the mockup.
  Widget _buildTabs({required bool sample}) {
    final low = _products.where((p) => p.stockQuantity <= _lowStock).length;
    Widget tab(int i, String label) {
      final on = _tab == i;
      return Padding(
        padding: const EdgeInsets.only(right: 22),
        child: GestureDetector(
          onTap: sample ? null : () => setState(() => _tab = i),
          child: Container(
            padding: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: on ? Colors.blue[900]! : Colors.transparent, width: 2),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: on ? FontWeight.bold : FontWeight.w500,
                color: on ? Colors.blue[900] : Colors.grey[600],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          tab(0, 'Recent sales'),
          tab(1, low > 0 ? 'Low stock ($low)' : 'Low stock'),
        ],
      ),
    );
  }

  Widget _lowStockList() {
    final low = _products.where((p) => p.stockQuantity <= _lowStock).toList()
      ..sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));
    if (low.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Text(tr('All items are well stocked.'),
            style: TextStyle(color: Colors.grey[600])),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: low.take(10).map((p) {
          final out = p.stockQuantity <= 0;
          final c = out ? Colors.red : Colors.orange;
          return _transactionTile(
            icon: Icons.inventory_2_outlined,
            iconColor: c,
            title: p.title,
            subtitle: out ? tr('Out of stock') : tr('Low stock'),
            amount: '${p.stockQuantity} left',
            time: tzs(p.price),
          );
        }).toList(),
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
            Text(tr('Sample'), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ],
      ),
    );
  }

  /// The 5 newest orders (fetchSales returns newest first). One order = everything
  /// sold in one checkout; an order with several products opens to list them.
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
        children: Order.group(_sales).take(5).map(_orderTile).toList(),
      ),
    );
  }

  Widget _orderTile(Order order) {
    final method = order.method.label;
    final color = order.method.color;
    final icon = order.method.icon;
    final number = order.number;

    if (order.isSingle) {
      final line = order.first;
      return _transactionTile(
        icon: icon,
        iconColor: color,
        title: line.productTitle,
        subtitle: '${number == null ? '' : 'Order $number  •  '}'
            '${line.quantity} item${line.quantity == 1 ? '' : 's'}  •  $method',
        amount: tzs(order.total),
        time: _timeAgo(order.time),
      );
    }

    // Several products: one card that opens to show every item sold.
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(15),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('home-order-${order.orderNo ?? order.first.id}'),
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          title: Text(number == null ? 'Order' : 'Order $number',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            '${order.productCount} products  •  ${order.itemCount} items  •  $method',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(tzs(order.total),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(_timeAgo(order.time),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more),
            ],
          ),
          children: [
            for (final l in order.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.productTitle,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          Text(
                            '${l.quantity} × ${tzs(l.quantity > 0 ? l.total / l.quantity : l.total)}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(tzs(l.total),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
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
            title: tr('Sample product'),
            subtitle: '2 items  •  Cash',
            amount: 'TZS 105,000',
            time: '2 mins ago',
          ),
          _transactionTile(
            icon: Icons.smartphone,
            iconColor: _mobileColor,
            title: tr('Sample product'),
            subtitle: '1 item  •  Mobile/Card',
            amount: 'TZS 45,000',
            time: '1 hr ago',
          ),
          _transactionTile(
            icon: Icons.payments,
            iconColor: _cashColor,
            title: tr('Sample product'),
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
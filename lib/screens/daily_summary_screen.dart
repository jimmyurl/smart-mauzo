import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/credit.dart';
import '../models/order.dart';
import '../models/sale.dart';
import '../services/credit_service.dart';
import '../services/offline_store.dart';
import '../services/shop_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../utils/money.dart';
import '../widgets/offline_data_banner.dart';
import '../widgets/pending_sync_banner.dart';

/// End-of-day summary: for one day, how much each person sold, split into cash
/// and mobile/card, so the owner can check the cash in the drawer.
/// Owners see every cashier; a cashier only sees their own sales (the database
/// already limits what a cashier receives).
class DailySummaryScreen extends StatefulWidget {
  const DailySummaryScreen({super.key});

  @override
  State<DailySummaryScreen> createState() => _DailySummaryScreenState();
}

class _SellerTotals {
  final String? userId;
  int orders = 0;
  int items = 0;
  double cash = 0;
  double mobile = 0;
  double credit = 0; // sold on credit: money still owed, not in the drawer
  double debtPaid = 0; // old debts paid back today
  _SellerTotals(this.userId);
  double get total => cash + mobile + credit;
  /// Cash that should be in the drawer: cash sales plus old debts paid back today.
  double get cashInHand => cash + debtPaid;
}

class _DailySummaryScreenState extends State<DailySummaryScreen> {
  static const _navy = Color(0xFF0D47A1);
  static const _cashColor = Color(0xFF2E7D32);
  static const _mobileColor = Color(0xFF1565C0);

  final SupabaseService _api = SupabaseService();

  List<Sale> _sales = [];
  bool _fromCache = false; // showing the copy saved on this phone
  DateTime? _savedAt;
  List<CreditEntry> _credit = [];
  List<TeamMember> _team = [];
  DateTime _day = DateTime.now();
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    SyncService().syncedTick.addListener(_onSynced);
    _load();
    _loadTeam();
    _loadCredit();
  }

  @override
  void dispose() {
    SyncService().syncedTick.removeListener(_onSynced);
    super.dispose();
  }

  void _onSynced() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    _loadCredit();
    try {
      final load = await _api.fetchSalesOrCached();
      if (!mounted) return;
      setState(() {
        _sales = load.sales;
        _fromCache = load.fromCache;
        _savedAt = load.savedAt;
        _error = '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// Credit sales and debt payments of the chosen day (empty if offline).
  Future<void> _loadCredit() async {
    final start = DateTime(_day.year, _day.month, _day.day);
    try {
      final list = await CreditService()
          .entriesBetween(start, start.add(const Duration(days: 1)));
      if (mounted) setState(() => _credit = list);
    } catch (_) {
      if (mounted) setState(() => _credit = []);
    }
  }

  /// Names of the people in the shop (owners only). Fails quietly when offline.
  Future<void> _loadTeam() async {
    if (!OfflineIdentity.isOwner) return;
    try {
      final team = await ShopService().team();
      if (mounted) {
        setState(() => _team = [for (final m in team) if (m.userId != null) m]);
      }
    } catch (_) {}
  }

  String _sellerName(String? userId) {
    if (userId == OfflineIdentity.userId) return 'You';
    if (userId == null) return 'Before cashiers';
    for (final m in _team) {
      if (m.userId == userId) return m.label;
    }
    return 'Former cashier';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _isToday => _sameDay(_day, DateTime.now());

  List<Sale> get _daySales =>
      [for (final s in _sales) if (_sameDay(s.timestamp.toLocal(), _day)) s];

  /// One entry per seller, biggest total first.
  List<_SellerTotals> _totals(List<Sale> daySales) {
    final bySeller = <String?, _SellerTotals>{};
    for (final s in daySales) {
      final t = bySeller.putIfAbsent(s.soldBy, () => _SellerTotals(s.soldBy));
      t.items += s.quantity;
      if (s.isCredit) {
        t.credit += s.total;
      } else if (s.isMobile) {
        t.mobile += s.total;
      } else {
        t.cash += s.total;
      }
    }
    // An order (a whole cart) counts once, however many products it has.
    for (final o in Order.group(daySales)) {
      bySeller[o.soldBy]?.orders += 1;
    }
    for (final e in _credit) {
      final t = bySeller.putIfAbsent(e.createdBy, () => _SellerTotals(e.createdBy));
      if (!e.isSale) t.debtPaid += e.amount; // credit sales come from the sales list
    }
    final list = bySeller.values.toList()..sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _day = picked);
      _loadCredit();
    }
  }

  void _moveDay(int delta) {
    final next = DateTime(_day.year, _day.month, _day.day + delta);
    if (next.isAfter(DateTime.now())) return;
    setState(() => _day = next);
    _loadCredit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily summary'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Pick a day',
            onPressed: _pickDay,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          const PendingSyncBanner(),
          if (_fromCache) OfflineDataBanner(savedAt: _savedAt),
          _dayBar(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _dayBar() {
    final label = _isToday
        ? 'Today, ${DateFormat('d MMM yyyy').format(_day)}'
        : DateFormat('EEEE, d MMM yyyy').format(_day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _moveDay(-1),
          ),
          Expanded(
            child: InkWell(
              onTap: _pickDay,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _isToday ? null : () => _moveDay(1),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty && _sales.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final daySales = _daySales;
    if (daySales.isEmpty && _credit.isEmpty) {
      return const Center(child: Text('No sales on this day.'));
    }

    final totals = _totals(daySales);
    final sales = totals.fold<double>(0, (s, t) => s + t.total);
    final cash = totals.fold<double>(0, (s, t) => s + t.cashInHand);
    final creditGiven = totals.fold<double>(0, (s, t) => s + t.credit);
    final debtPaid = totals.fold<double>(0, (s, t) => s + t.debtPaid);
    final mobile = totals.fold<double>(0, (s, t) => s + t.mobile);
    final orders = totals.fold<int>(0, (s, t) => s + t.orders);
    final items = totals.fold<int>(0, (s, t) => s + t.items);
    final showPeople = OfflineIdentity.isOwner;
    final waiting = _isToday ? SyncService().pendingCount : 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _grandTotal(sales, cash, mobile, orders, items),
          if (creditGiven > 0 || debtPaid > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${creditGiven > 0 ? 'Sold on credit ${tzs(creditGiven)} (not in cash)' : ''}'
                '${creditGiven > 0 && debtPaid > 0 ? '  •  ' : ''}'
                '${debtPaid > 0 ? 'Old debts paid ${tzs(debtPaid)} (in cash)' : ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
          if (waiting > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '$waiting sale(s) are still waiting on a phone to reach the '
                'server and are not counted here yet.',
                style: TextStyle(fontSize: 12, color: Colors.orange[800]),
              ),
            ),
          if (showPeople) ...[
            const SizedBox(height: 20),
            const Text('Per person',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final t in totals) _sellerCard(t),
          ],
        ],
      ),
    );
  }

  Widget _grandTotal(double total, double cash, double mobile, int orders, int items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total sales', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(tzs(total),
              style: const TextStyle(
                  color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('$orders order${orders == 1 ? '' : 's'}  •  $items item${items == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _methodBox('Cash to collect', cash, Icons.payments)),
              const SizedBox(width: 10),
              Expanded(child: _methodBox('Mobile / Card', mobile, Icons.smartphone)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _methodBox(String label, double amount, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(tzs(amount),
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _sellerCard(_SellerTotals t) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(0xFFE3F2FD),
                  child: Icon(Icons.person, size: 18, color: _navy),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_sellerName(t.userId),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                Text(tzs(t.total),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: Text(
                '${t.orders} order${t.orders == 1 ? '' : 's'}  •  ${t.items} item${t.items == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _splitTile('Cash', t.cashInHand, _cashColor)),
                const SizedBox(width: 10),
                Expanded(child: _splitTile('Mobile / Card', t.mobile, _mobileColor)),
              ],
            ),
            if (t.credit > 0 || t.debtPaid > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${t.credit > 0 ? 'Credit ${tzs(t.credit)}' : ''}'
                  '${t.credit > 0 && t.debtPaid > 0 ? '  •  ' : ''}'
                  '${t.debtPaid > 0 ? 'Debts paid ${tzs(t.debtPaid)}' : ''}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _splitTile(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: color)),
          const SizedBox(height: 2),
          Text(tzs(amount),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
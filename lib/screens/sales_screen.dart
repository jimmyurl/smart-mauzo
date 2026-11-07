import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../services/supabase_service.dart';
import '../utils/money.dart';
import '../services/offline_store.dart';
import '../services/shop_service.dart';
import '../services/sync_service.dart';
import '../widgets/pending_sync_banner.dart';
import 'new_sale_screen.dart';

enum _Period { today, week, month, all, custom }

/// Sales report: pick a period, see totals, payment split, best sellers and
/// the sales grouped by day. The "New sale" button opens NewSaleScreen.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  static const _navy = Color(0xFF0D47A1);
  static const _cashColor = Color(0xFF2E7D32);
  static const _mobileColor = Color(0xFF1565C0);

  final SupabaseService _supabaseService = SupabaseService();
  List<Sale> _sales = [];
  bool _isLoading = true;
  String _errorMessage = '';
  _Period _period = _Period.today;
  DateTimeRange? _customRange; // set when the user picks dates on the calendar

  // Owner only: who made each sale, and an optional "show one person" filter.
  List<TeamMember> _team = [];
  String? _sellerFilter; // a user id, or null for everyone

  @override
  void initState() {
    super.initState();
    SyncService().syncedTick.addListener(_onSynced);
    _fetchSales();
    _loadTeam();
  }

  /// Names of the people in the shop (owners only; cashiers only ever see their
  /// own sales, so they need no names). Fails quietly when offline.
  Future<void> _loadTeam() async {
    if (!OfflineIdentity.isOwner) return;
    try {
      final team = await ShopService().team();
      if (mounted) setState(() => _team = team);
    } catch (_) {}
  }

  String _sellerName(String? userId) {
    if (userId == null) return 'Before cashiers';
    for (final m in _team) {
      if (m.userId == userId) {
        return userId == OfflineIdentity.userId ? 'You' : m.label;
      }
    }
    return userId == OfflineIdentity.userId ? 'You' : 'Former cashier';
  }

  @override
  void dispose() {
    SyncService().syncedTick.removeListener(_onSynced);
    super.dispose();
  }

  /// Waiting sales just reached the server: reload the list.
  void _onSynced() {
    if (mounted) _fetchSales();
  }

  Future<void> _fetchSales() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final sales = await _supabaseService.fetchSales();
      if (!mounted) return;
      setState(() {
        _sales = sales;
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

  Future<void> _newSale() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NewSaleScreen()),
    );
    if (mounted) _fetchSales();
  }

  // ----------------------------------------------------------------- helpers
  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime? get _periodStart {
    final today = _startOfDay(DateTime.now());
    switch (_period) {
      case _Period.today:
        return today;
      case _Period.week:
        return today.subtract(const Duration(days: 6));
      case _Period.month:
        return today.subtract(const Duration(days: 29));
      case _Period.all:
        return null;
      case _Period.custom:
        return _customRange == null ? null : _startOfDay(_customRange!.start);
    }
  }

  /// Exclusive upper bound (only used by the calendar range).
  DateTime? get _periodEnd {
    if (_period != _Period.custom || _customRange == null) return null;
    return _startOfDay(_customRange!.end).add(const Duration(days: 1));
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(start: _startOfDay(now), end: _startOfDay(now)),
      helpText: 'Select a day or a range',
      saveText: 'Show',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _period = _Period.custom;
    });
  }

  String get _periodLabel {
    switch (_period) {
      case _Period.today:
        return 'Today';
      case _Period.week:
        return 'Last 7 days';
      case _Period.month:
        return 'Last 30 days';
      case _Period.all:
        return 'All time';
      case _Period.custom:
        final r = _customRange;
        if (r == null) return 'Pick dates';
        final f = DateFormat('d MMM yyyy');
        return _startOfDay(r.start) == _startOfDay(r.end)
            ? f.format(r.start)
            : '${f.format(r.start)} - ${f.format(r.end)}';
    }
  }

  List<Sale> get _filtered {
    final start = _periodStart;
    final end = _periodEnd;
    return _sales.where((s) {
      final t = s.timestamp.toLocal();
      if (start != null && t.isBefore(start)) return false;
      if (end != null && !t.isBefore(end)) return false;
      if (_sellerFilter != null && s.soldBy != _sellerFilter) return false;
      return true;
    }).toList();
  }

  String _dayLabel(DateTime day) {
    final today = _startOfDay(DateTime.now());
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEE, d MMM yyyy').format(day);
  }

  /// Owner only: choose whose sales to look at.
  Widget _sellerBar() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Everyone'),
              selected: _sellerFilter == null,
              onSelected: (_) => setState(() => _sellerFilter = null),
            ),
          ),
          for (final m in _team)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_sellerName(m.userId)),
                selected: _sellerFilter == m.userId,
                onSelected: (_) => setState(() => _sellerFilter = m.userId),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: Text(OfflineIdentity.isOwner ? 'Sales' : 'My sales'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Search by date',
            onPressed: _pickDates,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchSales),
        ],
      ),
      body: Column(
        children: [
          const PendingSyncBanner(),
          if (OfflineIdentity.isOwner && _team.length > 1) _sellerBar(),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newSale,
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('New sale'),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchSales, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final sales = _filtered;

    return RefreshIndicator(
      onRefresh: _fetchSales,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _periodChips(),
          const SizedBox(height: 12),
          if (sales.isEmpty)
            _emptyState()
          else ...[
            _summaryCard(sales),
            const SizedBox(height: 12),
            _paymentSplit(sales),
            const SizedBox(height: 12),
            _topProducts(sales),
            const SizedBox(height: 20),
            ..._groupedList(sales),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- period chips
  Widget _periodChips() {
    final labels = {
      _Period.today: 'Today',
      _Period.week: '7 days',
      _Period.month: '30 days',
      _Period.all: 'All',
      _Period.custom: _period == _Period.custom ? _periodLabel : 'Pick date',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _Period.values.map((p) {
          final selected = p == _period;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(labels[p]!),
              selected: selected,
              showCheckmark: false,
              selectedColor: _navy,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              avatar: p == _Period.custom
                  ? Icon(Icons.calendar_month,
                      size: 18, color: selected ? Colors.white : _navy)
                  : null,
              onSelected: (_) {
                if (p == _Period.custom) {
                  _pickDates();
                } else {
                  setState(() => _period = p);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.receipt_long, size: 56, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            _sales.isEmpty
                ? 'No sales yet.\nTap "New sale" to make your first one.'
                : 'No sales in this period.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- summary card
  Widget _summaryCard(List<Sale> sales) {
    final revenue = sales.fold<double>(0, (s, e) => s + e.total);
    final items = sales.fold<int>(0, (s, e) => s + e.quantity);
    final average = revenue / sales.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_periodLabel, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              tzs(revenue),
              style: const TextStyle(
                  color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat('Sales', '${sales.length}'),
              _stat('Items sold', '$items'),
              _stat('Average', tzs(average)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- payment split
  Widget _paymentSplit(List<Sale> sales) {
    double cash = 0, mobile = 0;
    for (final s in sales) {
      if (s.isMobile) {
        mobile += s.total;
      } else {
        cash += s.total;
      }
    }
    final total = cash + mobile;

    return _card(
      title: 'Payment methods',
      child: Column(
        children: [
          if (total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    if (cash > 0)
                      Expanded(
                          flex: (cash * 1000 / total).round().clamp(1, 1000).toInt(),
                          child: Container(color: _cashColor)),
                    if (mobile > 0)
                      Expanded(
                          flex: (mobile * 1000 / total).round().clamp(1, 1000).toInt(),
                          child: Container(color: _mobileColor)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _methodTile('Cash', Icons.payments, _cashColor, cash)),
              const SizedBox(width: 12),
              Expanded(
                  child: _methodTile(
                      'Mobile / Card', Icons.smartphone, _mobileColor, mobile)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _methodTile(String label, IconData icon, Color color, double amount) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(tzs(amount),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ top products
  Widget _topProducts(List<Sale> sales) {
    final byProduct = <String, _ProductTotal>{};
    for (final s in sales) {
      final t = byProduct.putIfAbsent(s.productId, () => _ProductTotal(s.productTitle));
      t.revenue += s.total;
      t.quantity += s.quantity;
    }
    final top = byProduct.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    final shown = top.take(5).toList();
    final maxRevenue = shown.first.revenue;

    return _card(
      title: 'Best sellers',
      child: Column(
        children: shown.map((p) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(p.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(width: 8),
                    Text(tzs(p.revenue),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maxRevenue <= 0 ? 0 : p.revenue / maxRevenue,
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text('${p.quantity} sold',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ------------------------------------------------------- grouped sales list
  List<Widget> _groupedList(List<Sale> sales) {
    // sales arrive newest first, so insertion order keeps days newest first.
    final days = <DateTime, List<Sale>>{};
    for (final s in sales) {
      days.putIfAbsent(_startOfDay(s.timestamp.toLocal()), () => []).add(s);
    }

    final widgets = <Widget>[];
    days.forEach((day, list) {
      final dayTotal = list.fold<double>(0, (s, e) => s + e.total);
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(_dayLabel(day),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            Text('${list.length} sale${list.length == 1 ? '' : 's'}  •  ${tzs(dayTotal)}',
                style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          ],
        ),
      ));
      widgets.add(Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.only(bottom: 16),
        child: Column(
          children: [
            for (var i = 0; i < list.length; i++) ...[
              _saleTile(list[i]),
              if (i != list.length - 1) const Divider(height: 1, indent: 68),
            ],
          ],
        ),
      ));
    });
    return widgets;
  }

  Widget _saleTile(Sale sale) {
    final color = sale.isMobile ? _mobileColor : _cashColor;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Icon(sale.isMobile ? Icons.smartphone : Icons.payments, color: color),
      ),
      title: Text(sale.productTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${sale.quantity} item${sale.quantity == 1 ? '' : 's'}  •  '
        '${DateFormat('HH:mm').format(sale.timestamp.toLocal())}  •  '
        '${sale.isMobile ? 'Mobile/Card' : 'Cash'}'
        '${OfflineIdentity.isOwner ? '  •  ${_sellerName(sale.soldBy)}' : ''}',
      ),
      trailing: Text(tzs(sale.total), style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ProductTotal {
  final String title;
  double revenue = 0;
  int quantity = 0;
  _ProductTotal(this.title);
}
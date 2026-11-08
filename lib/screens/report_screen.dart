import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../models/sale.dart';
import '../services/offline_store.dart';
import '../services/supabase_service.dart';
import '../utils/money.dart';
import '../utils/payment_style.dart';

enum _Period { today, week, month, year, custom }

/// Reports: pick a period (or any date / date range from the calendar), see
/// revenue AND profit compared with the previous period, a sales/profit chart,
/// payment split and best sellers (Overview tab), plus every transaction in
/// that period (Transactions tab).
///
/// Profit is calculated from `Sale.buyingPrice` (buying price per unit, saved on
/// the sale at the moment it was made). Sales without a buying price are left
/// out of profit so old data does not inflate the margin.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const _navy = Color(0xFF0D47A1);
  static const _cashColor = Color(0xFF2E7D32);
  static const _mobileColor = Color(0xFF1565C0);
  static const _profitColor = Color(0xFF2E7D32);
  static const _lossColor = Color(0xFFC62828);

  final SupabaseService _supabaseService = SupabaseService();

  List<Sale> _allSales = [];
  bool _isLoading = true;
  String _errorMessage = '';
  _Period _period = _Period.today;
  DateTimeRange? _customRange; // set when the user picks dates from the calendar
  bool _showProfit = false; // chart: sales vs profit
  bool _sellersByProfit = false; // best sellers: by sales vs by profit
  int? _selectedBar;

  @override
  void initState() {
    super.initState();
    _fetchSales();
  }

  /// Fetches once; changing the period only re-filters what is already loaded.
  Future<void> _fetchSales() async {
    try {
      final sales = await _supabaseService.fetchSales();
      if (!mounted) return;
      setState(() {
        _allSales = sales;
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

  // ------------------------------------------------------------------ profit
  /// A sale only counts towards profit when its buying price is known.
  bool _hasCost(Sale s) => s.buyingPrice > 0;
  double _costOf(Sale s) => s.buyingPrice * s.quantity;
  double _profitOf(Sale s) => _hasCost(s) ? s.total - _costOf(s) : 0;

  _Fin _fin(Iterable<Sale> sales) {
    final f = _Fin();
    for (final s in sales) {
      if (_hasCost(s)) {
        f.revenue += s.total;
        f.cost += _costOf(s);
        f.known++;
      } else {
        f.missing++;
      }
    }
    return f;
  }

  // ----------------------------------------------------------------- periods
  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _daysAgo(int n) {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day - n);
  }

  DateTimeRange get _range {
    final today = _startOfDay(DateTime.now());
    return _customRange ?? DateTimeRange(start: today, end: today);
  }

  /// Number of days in the selected period.
  int get _periodDays => (_end.difference(_start).inHours / 24).round();

  /// Start of the selected period (inclusive).
  DateTime get _start {
    final now = DateTime.now();
    switch (_period) {
      case _Period.today:
        return _daysAgo(0);
      case _Period.week:
        return _daysAgo(6);
      case _Period.month:
        return _daysAgo(29);
      case _Period.year:
        return DateTime(now.year, now.month - 11, 1);
      case _Period.custom:
        return _startOfDay(_range.start);
    }
  }

  /// End of the selected period (exclusive: midnight after the last day).
  DateTime get _end {
    final d = _period == _Period.custom ? _range.end : DateTime.now();
    return DateTime(d.year, d.month, d.day + 1);
  }

  /// Start of the period just before the selected one (same length).
  DateTime get _prevStart {
    final now = DateTime.now();
    switch (_period) {
      case _Period.today:
        return _daysAgo(1);
      case _Period.week:
        return _daysAgo(13);
      case _Period.month:
        return _daysAgo(59);
      case _Period.year:
        return DateTime(now.year, now.month - 23, 1);
      case _Period.custom:
        final s = _start;
        return DateTime(s.year, s.month, s.day - _periodDays);
    }
  }

  String _rangeText({bool short = false}) {
    final r = _range;
    if (_sameDay(r.start, r.end)) {
      return DateFormat(short ? 'd MMM yyyy' : 'EEE, d MMM yyyy').format(r.start);
    }
    final sameYear = r.start.year == r.end.year;
    final from = DateFormat(sameYear ? 'd MMM' : 'd MMM yyyy').format(r.start);
    final to = DateFormat('d MMM yyyy').format(r.end);
    return '$from – $to';
  }

  String get _periodLabel {
    switch (_period) {
      case _Period.today:
        return 'Today';
      case _Period.week:
        return 'Last 7 days';
      case _Period.month:
        return 'Last 30 days';
      case _Period.year:
        return 'Last 12 months';
      case _Period.custom:
        return _rangeText();
    }
  }

  String get _previousLabel {
    switch (_period) {
      case _Period.today:
        return 'yesterday';
      case _Period.week:
        return 'the previous 7 days';
      case _Period.month:
        return 'the previous 30 days';
      case _Period.year:
        return 'the previous 12 months';
      case _Period.custom:
        final n = _periodDays;
        return n <= 1 ? 'the previous day' : 'the previous $n days';
    }
  }

  List<Sale> _between(DateTime from, DateTime to) {
    return _allSales.where((s) {
      final t = s.timestamp.toLocal();
      return !t.isBefore(from) && t.isBefore(to);
    }).toList();
  }

  List<Sale> get _sales => _between(_start, _end);
  List<Sale> get _previousSales => _between(_prevStart, _start);

  String _dayLabel(DateTime day) {
    final diff = _startOfDay(DateTime.now()).difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEE, d MMM yyyy').format(day);
  }

  // ---------------------------------------------------------------- calendar
  /// Opens the calendar. Tap one day twice for a single date, or tap a start
  /// and an end day for a range.
  Future<void> _pickDates() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: _customRange,
      helpText: 'Pick a date or a range',
      saveText: 'Apply',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: _navy),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _period = _Period.custom;
      _selectedBar = null;
    });
  }

  // ------------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        appBar: AppBar(
          title: const Text('Reports'),
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.calendar_month),
              tooltip: 'Pick date',
              onPressed: _pickDates,
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _retry),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Transactions'),
            ],
          ),
        ),
        body: _buildBody(),
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
              ElevatedButton(onPressed: _retry, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final sales = _sales;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(alignment: Alignment.centerLeft, child: _periodChips()),
        ),
        Expanded(
          child: TabBarView(
            children: [
              _overviewTab(sales),
              _transactionsTab(sales),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- period chips
  Widget _periodChips() {
    const labels = {
      _Period.today: 'Today',
      _Period.week: 'Week',
      _Period.month: 'Month',
      _Period.year: 'Year',
    };
    final customSelected = _period == _Period.custom;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final e in labels.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: e.key == _period,
                showCheckmark: false,
                selectedColor: _navy,
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: e.key == _period ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) => setState(() {
                  _period = e.key;
                  _selectedBar = null;
                }),
              ),
            ),
          // Calendar chip: opens the date picker; shows the chosen dates.
          ChoiceChip(
            avatar: Icon(Icons.calendar_month,
                size: 18, color: customSelected ? Colors.white : _navy),
            label: Text(customSelected ? _rangeText(short: true) : 'Pick date'),
            selected: customSelected,
            showCheckmark: false,
            selectedColor: _navy,
            backgroundColor: Colors.white,
            labelStyle: TextStyle(
              color: customSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (_) => _pickDates(),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.bar_chart, size: 56, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            _allSales.isEmpty
                ? 'No sales yet.\nReports will appear after your first sale.'
                : 'No sales in this period.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ overview tab
  Widget _overviewTab(List<Sale> sales) {
    return RefreshIndicator(
      onRefresh: _fetchSales,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (sales.isEmpty)
            _emptyState()
          else ...[
            _summaryCard(sales),
            const SizedBox(height: 12),
            _profitCard(sales),
            const SizedBox(height: 12),
            _chartCard(sales),
            const SizedBox(height: 12),
            _paymentSplit(sales),
            const SizedBox(height: 12),
            _topProducts(sales),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- summary card
  Widget _summaryCard(List<Sale> sales) {
    final revenue = sales.fold<double>(0, (s, e) => s + e.total);
    final items = sales.fold<int>(0, (s, e) => s + e.quantity);
    final orderCount = Order.group(sales).length;
    final average = revenue / orderCount;
    final prev = _previousSales.fold<double>(0, (s, e) => s + e.total);

    Widget comparison;
    if (prev > 0) {
      final pct = ((revenue - prev) / prev * 100).round();
      final up = pct >= 0;
      comparison = Row(
        children: [
          Icon(up ? Icons.trending_up : Icons.trending_down,
              size: 18, color: up ? Colors.greenAccent : Colors.orangeAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${up ? '+' : ''}$pct% compared with $_previousLabel',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      );
    } else {
      comparison = Text(
        'No sales $_previousLabel to compare with',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      );
    }

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
          const SizedBox(height: 8),
          comparison,
          const SizedBox(height: 16),
          Row(
            children: [
              _stat('Orders', '$orderCount'),
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

  // -------------------------------------------------------------- profit card
  Widget _profitCard(List<Sale> sales) {
    // Profit is for the shop owner only; cashiers get no buying prices at all.
    if (!OfflineIdentity.isOwner) return const SizedBox.shrink();
    final fin = _fin(sales);

    if (fin.known == 0) {
      return _card(
        title: 'Profit',
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.grey[500]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No buying prices were recorded for these sales. Add a buying '
                'price to your items to see profit and margin here.',
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final profit = fin.profit;
    final loss = profit < 0;
    final color = loss ? _lossColor : _profitColor;

    final prev = _fin(_previousSales);
    Widget? compare;
    if (prev.known > 0 && prev.profit > 0) {
      final pct = ((profit - prev.profit) / prev.profit * 100).round();
      compare = Text(
        '${pct >= 0 ? '+' : ''}$pct% compared with $_previousLabel',
        style: TextStyle(color: Colors.grey[700], fontSize: 13),
      );
    }

    final costFlex = (fin.cost / fin.revenue * 1000).round().clamp(1, 999).toInt();

    return _card(
      title: 'Profit',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tzs(profit),
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${fin.margin.toStringAsFixed(1)}% margin',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          if (compare != null) ...[const SizedBox(height: 4), compare],
          const SizedBox(height: 14),
          if (!loss)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    Expanded(flex: costFlex, child: Container(color: Colors.grey[400])),
                    Expanded(flex: 1000 - costFlex, child: Container(color: _profitColor)),
                  ],
                ),
              ),
            ),
          if (!loss) const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _miniStat('Revenue', tzs(fin.revenue), Colors.black87)),
              Expanded(child: _miniStat('Buying cost', tzs(fin.cost), Colors.grey[700]!)),
            ],
          ),
          if (fin.missing > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Profit only counts sales that have a buying price. '
              '${fin.missing} sale${fin.missing == 1 ? '' : 's'} without one '
              '${fin.missing == 1 ? 'is' : 'are'} left out.',
              style: TextStyle(color: Colors.orange[800], fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: color)),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- chart
  List<_Bar> _bars(List<Sale> sales, bool profitMode) {
    final now = DateTime.now();
    double value(Sale s) => profitMode ? _profitOf(s) : s.total;

    List<_Bar> hourly() {
      final byHour = <int, double>{};
      for (final s in sales) {
        final h = s.timestamp.toLocal().hour;
        byHour[h] = (byHour[h] ?? 0) + value(s);
      }
      return List.generate(24, (h) {
        final from = '${h.toString().padLeft(2, '0')}:00';
        final to = '${((h + 1) % 24).toString().padLeft(2, '0')}:00';
        return _Bar(
          label: from,
          fullLabel: '$from - $to',
          value: byHour[h] ?? 0,
          showLabel: h % 6 == 0,
        );
      });
    }

    List<_Bar> daily(DateTime first, int days) {
      final byDay = <DateTime, double>{};
      for (final s in sales) {
        final d = _startOfDay(s.timestamp.toLocal());
        byDay[d] = (byDay[d] ?? 0) + value(s);
      }
      final step = days <= 7 ? 1 : (days / 5).ceil();
      return List.generate(days, (i) {
        final day = DateTime(first.year, first.month, first.day + i);
        return _Bar(
          label: days <= 7 ? DateFormat('E').format(day) : DateFormat('d MMM').format(day),
          fullLabel: DateFormat('EEE, d MMM').format(day),
          value: byDay[day] ?? 0,
          showLabel: i % step == 0,
        );
      });
    }

    List<_Bar> monthly(DateTime first, int count) {
      final byMonth = <DateTime, double>{};
      for (final s in sales) {
        final t = s.timestamp.toLocal();
        final key = DateTime(t.year, t.month, 1);
        byMonth[key] = (byMonth[key] ?? 0) + value(s);
      }
      final step = count <= 12 ? 1 : (count / 6).ceil();
      return List.generate(count, (i) {
        final month = DateTime(first.year, first.month + i, 1);
        return _Bar(
          label: DateFormat(count > 12 ? 'MMM yy' : 'MMM').format(month),
          fullLabel: DateFormat('MMMM yyyy').format(month),
          value: byMonth[month] ?? 0,
          showLabel: i % step == 0,
        );
      });
    }

    switch (_period) {
      case _Period.today:
        return hourly();
      case _Period.week:
        return daily(_daysAgo(6), 7);
      case _Period.month:
        return daily(_daysAgo(29), 30);
      case _Period.year:
        return monthly(DateTime(now.year, now.month - 11, 1), 12);
      case _Period.custom:
        final days = _periodDays;
        if (days <= 1) return hourly();
        if (days <= 31) return daily(_start, days);
        final last = DateTime(_end.year, _end.month, _end.day - 1);
        final count = (last.year - _start.year) * 12 + last.month - _start.month + 1;
        return monthly(DateTime(_start.year, _start.month, 1), count);
    }
  }

  Widget _toggle({
    required bool value,
    required String off,
    required String on,
    required ValueChanged<bool> onChanged,
  }) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        ButtonSegment(value: false, label: Text(off)),
        ButtonSegment(value: true, label: Text(on)),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }

  Widget _chartCard(List<Sale> sales) {
    final hasCost = sales.any(_hasCost);
    final profitMode = _showProfit && hasCost;
    final base = profitMode ? _profitColor : _navy;

    final bars = _bars(sales, profitMode);
    final maxValue = bars.fold<double>(0, (m, b) => math.max(m, b.value));
    final maxIndex = bars.indexWhere((b) => b.value == maxValue);
    const chartHeight = 140.0;

    final selected = (_selectedBar != null && _selectedBar! < bars.length)
        ? _selectedBar
        : null;
    final highlight = selected ?? (maxValue > 0 ? maxIndex : null);

    String caption;
    if (selected != null) {
      caption = '${bars[selected].fullLabel}  •  ${tzs(bars[selected].value)}';
    } else if (maxValue > 0) {
      caption = 'Best: ${bars[maxIndex].fullLabel}  •  ${tzs(maxValue)}';
    } else {
      caption = profitMode ? 'No profit to chart' : 'No sales to chart';
    }

    final thin = bars.length > 12;

    return _card(
      title: profitMode ? 'Profit over time' : 'Sales over time',
      trailing: hasCost
          ? _toggle(
              value: profitMode,
              off: 'Sales',
              on: 'Profit',
              onChanged: (v) => setState(() {
                _showProfit = v;
                _selectedBar = null;
              }),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          const SizedBox(height: 12),
          SizedBox(
            height: chartHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < bars.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _selectedBar = i),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: thin ? 1 : 4),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: maxValue <= 0
                                ? 3
                                : math.max(3, bars[i].value / maxValue * chartHeight),
                            decoration: BoxDecoration(
                              color: i == highlight ? base : base.withOpacity(0.3),
                              borderRadius:
                                  const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 16,
            child: Row(
              children: [
                for (final b in bars)
                  Expanded(
                    child: b.showLabel
                        ? OverflowBox(
                            maxWidth: 56,
                            child: Text(
                              b.label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(color: Colors.grey[600], fontSize: 10),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- payment split
  Widget _paymentSplit(List<Sale> sales) {
    double cash = 0, mobile = 0, credit = 0;
    for (final s in sales) {
      if (s.isCredit) {
        credit += s.total;
      } else if (s.isMobile) {
        mobile += s.total;
      } else {
        cash += s.total;
      }
    }
    final total = cash + mobile + credit;

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
                    if (credit > 0)
                      Expanded(
                          flex: (credit * 1000 / total).round().clamp(1, 1000).toInt(),
                          child: Container(color: kCreditColor)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _methodTile('Cash', Icons.payments, _cashColor, cash, total)),
              const SizedBox(width: 12),
              Expanded(
                  child: _methodTile(
                      'Mobile / Card', Icons.smartphone, _mobileColor, mobile, total)),
            ],
          ),
          if (credit > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _methodTile('Credit (not paid yet)', Icons.menu_book_outlined, kCreditColor, credit, total),
            ),
        ],
      ),
    );
  }

  Widget _methodTile(String label, IconData icon, Color color, double amount, double total) {
    final share = total <= 0 ? 0 : (amount / total * 100).round();
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
              Text('$label  •  $share%',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(tzs(amount), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ top products
  Widget _topProducts(List<Sale> sales) {
    final hasCost = sales.any(_hasCost);
    final byProfit = _sellersByProfit && hasCost;

    final byProduct = <String, _ProductTotal>{};
    for (final s in sales) {
      final t = byProduct.putIfAbsent(s.productId, () => _ProductTotal(s.productTitle));
      t.revenue += s.total;
      t.quantity += s.quantity;
      if (_hasCost(s)) {
        t.knownRevenue += s.total;
        t.cost += _costOf(s);
      }
    }

    double metric(_ProductTotal p) => byProfit ? p.profit : p.revenue;
    final top = byProduct.values.toList()..sort((a, b) => metric(b).compareTo(metric(a)));
    final shown = top.take(5).toList();
    final maxValue = metric(shown.first);
    final barColor = byProfit ? _profitColor : _navy;

    String subtitle(_ProductTotal p) {
      var text = '${p.quantity} sold';
      if (byProfit) {
        text += '  •  Sales ${tzs(p.revenue)}';
        text += p.hasCost
            ? '  •  ${p.margin.toStringAsFixed(0)}% margin'
            : '  •  No buying price';
      } else if (hasCost) {
        text += p.hasCost
            ? '  •  Profit ${tzs(p.profit)} (${p.margin.toStringAsFixed(0)}%)'
            : '  •  No buying price';
      }
      return text;
    }

    return _card(
      title: byProfit ? 'Most profitable' : 'Best sellers',
      trailing: hasCost
          ? _toggle(
              value: byProfit,
              off: 'Sales',
              on: 'Profit',
              onChanged: (v) => setState(() => _sellersByProfit = v),
            )
          : null,
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${i + 1}. ${shown[i].title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(width: 8),
                      Text(tzs(metric(shown[i])),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxValue <= 0
                          ? 0
                          : (metric(shown[i]) / maxValue).clamp(0.0, 1.0).toDouble(),
                      minHeight: 6,
                      backgroundColor: Colors.grey[200],
                      color: barColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle(shown[i]),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- transactions tab
  Widget _transactionsTab(List<Sale> sales) {
    final orderCount = Order.group(sales).length;
    return RefreshIndicator(
      onRefresh: _fetchSales,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (sales.isEmpty)
            _emptyState()
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                '$orderCount order${orderCount == 1 ? '' : 's'}  •  $_periodLabel',
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            ),
            ..._groupedList(sales),
          ],
        ],
      ),
    );
  }

  List<Widget> _groupedList(List<Sale> sales) {
    // sales arrive newest first, so insertion order keeps days newest first.
    final days = <DateTime, List<Order>>{};
    for (final o in Order.group(sales)) {
      days.putIfAbsent(_startOfDay(o.time.toLocal()), () => []).add(o);
    }

    final widgets = <Widget>[];
    days.forEach((day, list) {
      final dayTotal = list.fold<double>(0, (s, e) => s + e.total);
      final fin = _fin([for (final o in list) ...o.lines]);
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(_dayLabel(day),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${list.length} order${list.length == 1 ? '' : 's'}  •  ${tzs(dayTotal)}',
                    style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                if (fin.known > 0)
                  Text('Profit ${tzs(fin.profit)}',
                      style: TextStyle(
                          color: fin.profit < 0 ? _lossColor : _profitColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ));
      widgets.add(Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.only(bottom: 16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < list.length; i++) ...[
              _orderTile(list[i]),
              if (i != list.length - 1) const Divider(height: 1, indent: 68),
            ],
          ],
        ),
      ));
    });
    return widgets;
  }

  /// One row per order. An order with several products opens like an accordion
  /// to show every item sold in it; tap an item for its full details.
  Widget _orderTile(Order order) {
    if (order.isSingle) return _saleTile(order.first);

    final color = order.method.color;
    final profit = order.lines.fold<double>(0, (s, l) => s + _profitOf(l));
    final hasCost = order.lines.any(_hasCost);
    final number = order.number;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>('order-${order.orderNo ?? order.first.id}'),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(order.method.icon, color: color),
        ),
        title: Text(number == null ? 'Order' : 'Order $number',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${order.productCount} products  •  ${order.itemCount} items  •  '
          '${DateFormat('HH:mm').format(order.time.toLocal())}  •  '
          '${order.method.label}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(tzs(order.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                if (hasCost)
                  Text('+${tzs(profit)}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: profit < 0 ? _lossColor : _profitColor)),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF4F6FA),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final l in order.lines)
                  ListTile(
                    dense: true,
                    onTap: () => _showDetails(l),
                    title: Text(l.productTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${l.quantity} × ${tzs(l.quantity > 0 ? l.total / l.quantity : l.total)}',
                    ),
                    trailing: Text(tzs(l.total),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _saleTile(Sale sale) {
    final color = sale.method.color;
    final profit = _profitOf(sale);
    return ListTile(
      onTap: () => _showDetails(sale),
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Icon(sale.method.icon, color: color),
      ),
      title: Text(sale.productTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${sale.orderNo == null ? '' : 'Order ${orderLabel(sale.orderNo!)}  •  '}'
        '${sale.quantity} item${sale.quantity == 1 ? '' : 's'}  •  '
        '${DateFormat('HH:mm').format(sale.timestamp.toLocal())}  •  '
        '${sale.method.label}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(tzs(sale.total), style: const TextStyle(fontWeight: FontWeight.bold)),
          if (_hasCost(sale))
            Text('+${tzs(profit)}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: profit < 0 ? _lossColor : _profitColor)),
        ],
      ),
    );
  }

  // ------------------------------------------------------- transaction details
  void _showDetails(Sale sale) {
    final color = sale.method.color;
    final id = '${sale.id}';
    final shortId = (id.length > 8 ? id.substring(id.length - 8) : id).toUpperCase();
    final time = sale.timestamp.toLocal();
    final hasCost = _hasCost(sale);
    final profit = _profitOf(sale);
    final margin = (hasCost && sale.total > 0) ? profit / sale.total * 100 : 0.0;
    final unitPrice = sale.quantity > 0 ? sale.total / sale.quantity : sale.total;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withOpacity(0.12),
                    child: Icon(sale.method.icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(sale.productTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(tzs(sale.total),
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.bold, color: _navy)),
              const SizedBox(height: 16),
              const Divider(),
              _detailRow('Quantity', '${sale.quantity}'),
              _detailRow('Selling price (each)', tzs(unitPrice)),
              if (hasCost) ...[
                _detailRow('Buying price (each)', tzs(sale.buyingPrice)),
                _detailRow('Profit', tzs(profit),
                    valueColor: profit < 0 ? _lossColor : _profitColor),
                _detailRow('Margin', '${margin.toStringAsFixed(1)}%',
                    valueColor: profit < 0 ? _lossColor : _profitColor),
              ] else if (OfflineIdentity.isOwner)
                _detailRow('Buying price', 'Not recorded'),
              _detailRow('Payment', sale.isCredit ? 'Credit (debt)' : (sale.isMobile ? 'Mobile / Card' : 'Cash')),
              _detailRow('Date', DateFormat('EEE, d MMM yyyy').format(time)),
              _detailRow('Time', DateFormat('HH:mm').format(time)),
              _detailRow(sale.orderNo == null ? 'Receipt' : 'Order',
                  sale.orderNo == null ? '#$shortId' : orderLabel(sale.orderNo!)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          const Spacer(),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: valueColor)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ helpers
  Widget _card({required String title, required Widget child, Widget? trailing}) {
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
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Revenue / cost / profit of the sales that have a buying price.
class _Fin {
  double revenue = 0;
  double cost = 0;
  int known = 0; // sales with a buying price
  int missing = 0; // sales without one (left out of profit)
  double get profit => revenue - cost;
  double get margin => revenue <= 0 ? 0 : profit / revenue * 100;
}

class _ProductTotal {
  final String title;
  double revenue = 0;
  int quantity = 0;
  double knownRevenue = 0; // revenue from sales that have a buying price
  double cost = 0;
  _ProductTotal(this.title);

  bool get hasCost => knownRevenue > 0;
  double get profit => knownRevenue - cost;
  double get margin => knownRevenue <= 0 ? 0 : profit / knownRevenue * 100;
}

class _Bar {
  final String label; // short label under the bar
  final String fullLabel; // shown when the bar is tapped
  final double value;
  final bool showLabel;
  const _Bar({
    required this.label,
    required this.fullLabel,
    required this.value,
    required this.showLabel,
  });
}
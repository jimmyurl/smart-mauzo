import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../services/supabase_service.dart';
import '../utils/money.dart';

enum _Period { today, week, month, year }

/// Reports: pick a period, see revenue compared with the previous period,
/// a sales chart, payment split and best sellers (Overview tab), plus every
/// transaction in that period (Transactions tab).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const _navy = Color(0xFF0D47A1);
  static const _cashColor = Color(0xFF2E7D32);
  static const _mobileColor = Color(0xFF1565C0);

  final SupabaseService _supabaseService = SupabaseService();

  List<Sale> _allSales = [];
  bool _isLoading = true;
  String _errorMessage = '';
  _Period _period = _Period.today;
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

  // ----------------------------------------------------------------- periods
  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _daysAgo(int n) {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day - n);
  }

  /// Start of the selected period.
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
    }
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
    }
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
    }
  }

  List<Sale> get _sales {
    final start = _start;
    return _allSales.where((s) => !s.timestamp.toLocal().isBefore(start)).toList();
  }

  double get _previousRevenue {
    final start = _start;
    final prevStart = _prevStart;
    return _allSales.where((s) {
      final t = s.timestamp.toLocal();
      return !t.isBefore(prevStart) && t.isBefore(start);
    }).fold<double>(0, (sum, s) => sum + s.total);
  }

  String _dayLabel(DateTime day) {
    final diff = _startOfDay(DateTime.now()).difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEE, d MMM yyyy').format(day);
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
              onSelected: (_) => setState(() {
                _period = p;
                _selectedBar = null;
              }),
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
    final average = revenue / sales.length;
    final prev = _previousRevenue;

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

  // -------------------------------------------------------------------- chart
  List<_Bar> _bars(List<Sale> sales) {
    final now = DateTime.now();

    switch (_period) {
      case _Period.today:
        final byHour = <int, double>{};
        for (final s in sales) {
          final h = s.timestamp.toLocal().hour;
          byHour[h] = (byHour[h] ?? 0) + s.total;
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

      case _Period.week:
      case _Period.month:
        final days = _period == _Period.week ? 7 : 30;
        final byDay = <DateTime, double>{};
        for (final s in sales) {
          final d = _startOfDay(s.timestamp.toLocal());
          byDay[d] = (byDay[d] ?? 0) + s.total;
        }
        return List.generate(days, (i) {
          final ago = days - 1 - i;
          final day = _daysAgo(ago);
          return _Bar(
            label: days == 7 ? DateFormat('E').format(day) : DateFormat('d MMM').format(day),
            fullLabel: DateFormat('EEE, d MMM').format(day),
            value: byDay[day] ?? 0,
            showLabel: days == 7 ? true : ago % 7 == 0,
          );
        });

      case _Period.year:
        final byMonth = <DateTime, double>{};
        for (final s in sales) {
          final t = s.timestamp.toLocal();
          final key = DateTime(t.year, t.month, 1);
          byMonth[key] = (byMonth[key] ?? 0) + s.total;
        }
        return List.generate(12, (i) {
          final month = DateTime(now.year, now.month - 11 + i, 1);
          return _Bar(
            label: DateFormat('MMM').format(month),
            fullLabel: DateFormat('MMMM yyyy').format(month),
            value: byMonth[month] ?? 0,
            showLabel: true,
          );
        });
    }
  }

  Widget _chartCard(List<Sale> sales) {
    final bars = _bars(sales);
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
      caption = 'No sales to chart';
    }

    final thin = bars.length > 12;

    return _card(
      title: 'Sales over time',
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
                              color: i == highlight ? _navy : _navy.withOpacity(0.3),
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
              Expanded(child: _methodTile('Cash', Icons.payments, _cashColor, cash, total)),
              const SizedBox(width: 12),
              Expanded(
                  child: _methodTile(
                      'Mobile / Card', Icons.smartphone, _mobileColor, mobile, total)),
            ],
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
    final byProduct = <String, _ProductTotal>{};
    for (final s in sales) {
      final t = byProduct.putIfAbsent(s.productId, () => _ProductTotal(s.productTitle));
      t.revenue += s.total;
      t.quantity += s.quantity;
    }
    final top = byProduct.values.toList()..sort((a, b) => b.revenue.compareTo(a.revenue));
    final shown = top.take(5).toList();
    final maxRevenue = shown.first.revenue;

    return _card(
      title: 'Best sellers',
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
                      Text(tzs(shown[i].revenue),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxRevenue <= 0 ? 0 : shown[i].revenue / maxRevenue,
                      minHeight: 6,
                      backgroundColor: Colors.grey[200],
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('${shown[i].quantity} sold',
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
                '${sales.length} transaction${sales.length == 1 ? '' : 's'}  •  $_periodLabel',
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
        clipBehavior: Clip.antiAlias,
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
      onTap: () => _showDetails(sale),
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Icon(sale.isMobile ? Icons.smartphone : Icons.payments, color: color),
      ),
      title: Text(sale.productTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${sale.quantity} item${sale.quantity == 1 ? '' : 's'}  •  '
        '${DateFormat('HH:mm').format(sale.timestamp.toLocal())}  •  '
        '${sale.isMobile ? 'Mobile/Card' : 'Cash'}',
      ),
      trailing: Text(tzs(sale.total), style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  // ------------------------------------------------------- transaction details
  void _showDetails(Sale sale) {
    final color = sale.isMobile ? _mobileColor : _cashColor;
    final id = '${sale.id}';
    final shortId = (id.length > 8 ? id.substring(id.length - 8) : id).toUpperCase();
    final time = sale.timestamp.toLocal();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
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
                    child: Icon(sale.isMobile ? Icons.smartphone : Icons.payments, color: color),
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
              _detailRow('Payment', sale.isMobile ? 'Mobile / Card' : 'Cash'),
              _detailRow('Date', DateFormat('EEE, d MMM yyyy').format(time)),
              _detailRow('Time', DateFormat('HH:mm').format(time)),
              _detailRow('Receipt', '#$shortId'),
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

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ helpers
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
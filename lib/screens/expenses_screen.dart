import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../services/app_language.dart';
import '../services/expense_service.dart';
import '../utils/money.dart';
import '../widgets/add_expense_sheet.dart';

/// Owner only: what the shop spends (rent, salaries, transport...), month by month.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  static const _spendColor = Color(0xFFEF6C00);

  final _svc = ExpenseService();
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Expense>? _items;
  bool _loading = true;
  bool _failed = false;

  bool get _isCurrentMonth {
    final n = DateTime.now();
    return _month.year == n.year && _month.month == n.month;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final list = await _svc.list(_month, DateTime(_month.year, _month.month + 1));
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _shift(int by) {
    setState(() => _month = DateTime(_month.year, _month.month + by));
    _load();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _add() async {
    final saved = await showAddExpenseSheet(context);
    if (saved == true) _load();
  }

  Future<bool> _confirmDelete(Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Delete this expense?')),
        content: Text('${tr(expenseCategory(e.category).label)}: ${tzs(e.amount)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Delete'), style: TextStyle(color: Colors.red[700])),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await _svc.delete(e.id);
      return true;
    } catch (_) {
      _snack(tr('Could not delete. Check your internet and try again.'));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: Text(tr('Expenses'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(tr('Add expense')),
      ),
      body: Column(
        children: [
          _monthBar(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _monthBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          SizedBox(
            width: 170,
            child: Text(
              DateFormat('MMMM yyyy').format(_month),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            onPressed: _isCurrentMonth ? null : () => _shift(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _items == null) return const Center(child: CircularProgressIndicator());
    if (_failed && _items == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 40),
              const SizedBox(height: 12),
              Text(tr('Expenses need internet. Pull down to try again.'),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: Text(tr('Try again'))),
            ],
          ),
        ),
      );
    }

    final items = _items ?? const <Expense>[];
    final total = items.fold<double>(0, (s, e) => s + e.amount);
    final byCat = <String, double>{};
    for (final e in items) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Total expenses'), style: TextStyle(color: Colors.grey[600])),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(tzs(total),
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold, color: _spendColor)),
                ),
                if (cats.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(tr('By category'),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  for (final c in cats) _categoryRow(c.key, c.value, total),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('No expenses this month'),
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(tr('Swipe left to delete'),
                  style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ),
            for (final e in items) _tile(e),
          ],
        ],
      ),
    );
  }

  Widget _categoryRow(String key, double value, double total) {
    final c = expenseCategory(key);
    final share = total <= 0 ? 0.0 : value / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(c.icon, size: 18, color: Colors.grey[700]),
              const SizedBox(width: 8),
              Expanded(child: Text(tr(c.label), style: const TextStyle(fontSize: 13))),
              Text(tzs(value),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 6,
              backgroundColor: Colors.grey[200],
              color: _spendColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(Expense e) {
    final c = expenseCategory(e.category);
    final note = (e.note == null || e.note!.isEmpty) ? '' : '  -  ${e.note}';
    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(e),
      onDismissed: (_) => setState(() => _items?.removeWhere((x) => x.id == e.id)),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red[400],
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: _spendColor.withOpacity(0.12),
              child: Icon(c.icon, size: 20, color: _spendColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(c.label), style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${DateFormat('d MMM, HH:mm').format(e.spentAt.toLocal())}$note',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(tzs(e.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
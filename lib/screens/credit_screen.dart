import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/credit.dart';
import '../services/credit_service.dart';
import '../utils/money.dart';
import '../widgets/customer_picker.dart';
import '../widgets/reminder_sheet.dart';
import 'customer_ledger_screen.dart';
import '../services/app_language.dart';

/// The credit book (owners): everyone who owes the shop money, biggest debt first.
class CreditScreen extends StatefulWidget {
  const CreditScreen({super.key});

  @override
  State<CreditScreen> createState() => _CreditScreenState();
}

class _CreditScreenState extends State<CreditScreen> {
  static const _navy = Color(0xFF0D47A1);
  static const _owedColor = Color(0xFFC62828);

  List<CustomerBalance> _all = [];
  bool _loading = true;
  String _error = '';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await CreditService().balances();
      list.sort((a, b) {
        final byDebt = b.balance.compareTo(a.balance);
        return byDebt != 0 ? byDebt : a.customer.name.compareTo(b.customer.name);
      });
      if (!mounted) return;
      setState(() {
        _all = list;
        _error = '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = CreditService.message(e);
        _loading = false;
      });
    }
  }

  Future<void> _addCustomer() async {
    final c = await askNewCustomer(context);
    if (c != null) _load();
  }

  Future<void> _open(CustomerBalance b) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerLedgerScreen(start: b)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Credit book')),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomer,
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: Text(tr('Customer')),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty && _all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: Text(tr('Try again'))),
            ],
          ),
        ),
      );
    }

    final owing = _all.where((b) => b.balance > 0).toList();
    final totalOwed = owing.fold<double>(0, (s, b) => s + b.balance);
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final b in _all)
        if (q.isEmpty ||
            b.customer.name.toLowerCase().contains(q) ||
            (b.customer.phone ?? '').contains(q))
          b
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Total owed to you'), style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 4),
                Text(tzs(totalOwed),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  '${owing.length} customer${owing.length == 1 ? '' : 's'} with a debt',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: tr('Search customer'),
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          if (_all.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'No customers yet.\nAdd one here, or choose "Sell on credit" at checkout.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else if (shown.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text(tr('No customer matches your search.'))),
            )
          else
            for (final b in shown) _tile(b),
        ],
      ),
    );
  }

  Widget _tile(CustomerBalance b) {
    final owes = b.balance > 0;
    final details = [
      if (b.customer.phone != null) b.customer.phone!,
      if (b.lastActivity != null)
        'last ${DateFormat('d MMM').format(b.lastActivity!.toLocal())}',
    ].join('  •  ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _open(b),
      leading: CircleAvatar(
        backgroundColor: owes ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
        child: Text(
          b.customer.name.isEmpty ? '?' : b.customer.name[0].toUpperCase(),
          style: TextStyle(color: owes ? _owedColor : Colors.green[800]),
        ),
      ),
      title: Text(b.customer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty ? null : Text(details),
      trailing: owes
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tzs(b.balance),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: _owedColor)),
                IconButton(
                  tooltip: tr('Send reminder'),
                  icon: const Icon(Icons.chat_outlined, color: Color(0xFF25D366)),
                  onPressed: () =>
                      showReminderSheet(context, customer: b.customer, balance: b.balance),
                ),
              ],
            )
          : Text(tr('Cleared'), style: TextStyle(color: Colors.grey[600])),
    );
  }
}
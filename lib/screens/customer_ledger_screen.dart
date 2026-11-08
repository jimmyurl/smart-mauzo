import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/credit.dart';
import '../models/order.dart';
import '../services/credit_service.dart';
import '../utils/money.dart';

/// One customer's history: what they took on credit and what they paid, with
/// a button to record a payment. Owners only.
class CustomerLedgerScreen extends StatefulWidget {
  final CustomerBalance start;
  const CustomerLedgerScreen({super.key, required this.start});

  @override
  State<CustomerLedgerScreen> createState() => _CustomerLedgerScreenState();
}

class _CustomerLedgerScreenState extends State<CustomerLedgerScreen> {
  static const _navy = Color(0xFF0D47A1);
  static const _owedColor = Color(0xFFC62828);
  static const _paidColor = Color(0xFF2E7D32);

  List<CreditEntry> _entries = [];
  late double _balance = widget.start.balance;
  bool _loading = true;
  String _error = '';

  Customer get _customer => widget.start.customer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await CreditService().entries(_customer.id);
      var bal = 0.0;
      for (final e in list) {
        bal += e.isSale ? e.amount : -e.amount;
      }
      if (!mounted) return;
      setState(() {
        _entries = list;
        _balance = bal;
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

  void _snack(String text, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: ok ? Colors.green : null));
  }

  Future<void> _recordPayment() async {
    final result = await showDialog<_PaymentInput>(
      context: context,
      builder: (_) => _PaymentDialog(balance: _balance),
    );
    if (result == null) return;
    try {
      final left = await CreditService()
          .recordPayment(_customer.id, result.amount, note: result.note);
      _snack(
        left <= 0 ? 'Paid in full' : '${tzs(left)} still owed',
        ok: true,
      );
    } catch (e) {
      _snack('Payment not recorded: ${CreditService.message(e)}');
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final owes = _balance > 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(_customer.name, overflow: TextOverflow.ellipsis),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_customer.phone != null)
                          Row(children: [
                            Icon(Icons.phone_android, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 6),
                            Text(_customer.phone!),
                          ]),
                        const SizedBox(height: 8),
                        Text(owes ? 'Owes you' : 'No debt',
                            style: TextStyle(color: Colors.grey[600])),
                        Text(
                          tzs(owes ? _balance : 0),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: owes ? _owedColor : _paidColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: owes ? _recordPayment : null,
                            icon: const Icon(Icons.payments),
                            label: const Text('Record payment'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('History',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_error, style: const TextStyle(color: Colors.red)),
                    )
                  else if (_entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Nothing recorded yet.')),
                    )
                  else
                    for (final e in _entries) _entryTile(e),
                ],
              ),
            ),
    );
  }

  Widget _entryTile(CreditEntry e) {
    final when = DateFormat('d MMM yyyy, HH:mm').format(e.createdAt.toLocal());
    final title = e.isSale
        ? (e.orderNo == null ? 'Goods on credit' : 'Order ${orderLabel(e.orderNo!)} on credit')
        : 'Payment received';
    final sub = [when, if (e.note != null) e.note!].join('  •  ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: e.isSale ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
        child: Icon(
          e.isSale ? Icons.shopping_bag_outlined : Icons.payments,
          color: e.isSale ? _owedColor : _paidColor,
        ),
      ),
      title: Text(title),
      subtitle: Text(sub),
      trailing: Text(
        '${e.isSale ? '+' : '-'}${tzs(e.amount)}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: e.isSale ? _owedColor : _paidColor,
        ),
      ),
    );
  }
}

class _PaymentInput {
  final double amount;
  final String? note;
  const _PaymentInput(this.amount, this.note);
}

class _PaymentDialog extends StatefulWidget {
  final double balance;
  const _PaymentDialog({required this.balance});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (v == null || v <= 0) {
      setState(() => _error = 'Enter the amount received');
      return;
    }
    if (v > widget.balance) {
      setState(() => _error = 'More than the debt (${tzs(widget.balance)})');
      return;
    }
    Navigator.pop(context, _PaymentInput(v, _note.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Owes ${tzs(widget.balance)}', style: TextStyle(color: Colors.grey[700])),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Amount received',
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _amount.text = widget.balance.toStringAsFixed(0),
              child: const Text('Pay full balance'),
            ),
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'e.g. M-Pesa, cash',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
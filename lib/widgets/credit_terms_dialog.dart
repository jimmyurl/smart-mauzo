import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_language.dart';
import '../utils/money.dart';

/// What the customer pays at the counter when buying on credit.
class CreditTerms {
  final double paidNow; // 0 = nothing paid, the whole total becomes debt
  final String method; // 'cash' | 'mobile'
  const CreditTerms(this.paidNow, this.method);
}

/// Confirms a credit sale and lets the cashier enter an optional deposit.
/// Returns null if cancelled.
Future<CreditTerms?> askCreditTerms(
  BuildContext context, {
  required String customerName,
  required double total,
}) {
  return showDialog<CreditTerms>(
    context: context,
    builder: (_) => _CreditTermsDialog(customerName: customerName, total: total),
  );
}

class _CreditTermsDialog extends StatefulWidget {
  final String customerName;
  final double total;
  const _CreditTermsDialog({required this.customerName, required this.total});

  @override
  State<_CreditTermsDialog> createState() => _CreditTermsDialogState();
}

class _CreditTermsDialogState extends State<_CreditTermsDialog> {
  final _paid = TextEditingController();
  String _method = 'cash';
  String _error = '';

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_paid.text.replaceAll(',', '').trim()) ?? 0;

  void _confirm() {
    final v = _amount;
    if (v < 0 || v >= widget.total) {
      setState(() => _error = tr(
          'The deposit must be less than the total. If the customer pays everything, use Cash or Mobile money.'));
      return;
    }
    Navigator.pop(context, CreditTerms(v, _method));
  }

  @override
  Widget build(BuildContext context) {
    final paid = _amount;
    final debt = (paid > 0 && paid < widget.total) ? widget.total - paid : widget.total;
    return AlertDialog(
      title: Text(tr('Sell on credit')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${tr('Total')}: ${tzs(widget.total)}'),
            const SizedBox(height: 12),
            TextField(
              controller: _paid,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))],
              onChanged: (_) => setState(() => _error = ''),
              decoration: InputDecoration(
                labelText: tr('Paid now (optional)'),
                prefixText: 'TZS ',
                border: const OutlineInputBorder(),
              ),
            ),
            if (paid > 0) ...[
              const SizedBox(height: 10),
              Text(tr('How was the deposit paid?'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(tr('Cash')),
                    selected: _method == 'cash',
                    onSelected: (_) => setState(() => _method = 'cash'),
                  ),
                  ChoiceChip(
                    label: Text(tr('Mobile money')),
                    selected: _method == 'mobile',
                    onSelected: (_) => setState(() => _method = 'mobile'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${tr('Balance added to debt')}: ${tzs(debt)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF6C00)),
              ),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(onPressed: _confirm, child: Text(tr('Confirm'))),
      ],
    );
  }
}
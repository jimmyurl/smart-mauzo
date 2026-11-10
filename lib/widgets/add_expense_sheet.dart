import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/expense.dart';
import '../services/app_language.dart';
import '../services/expense_service.dart';

/// Asks for one expense and saves it. Returns true if it was saved.
Future<bool?> showAddExpenseSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AddExpenseSheet(),
  );
}

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet();

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final String _id = const Uuid().v4(); // same id on every retry of this expense
  String _category = 'rent';
  DateTime _date = DateTime.now();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;

  bool get _isToday {
    final n = DateTime.now();
    return _date.year == n.year && _date.month == n.month && _date.day == n.day;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now.subtract(const Duration(days: 366)),
      lastDate: now,
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final v = _value;
    if (v <= 0) {
      setState(() => _error = tr('Enter an amount greater than zero'));
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    // Today keeps the real time; an earlier day is saved at noon.
    final spentAt = _isToday ? DateTime.now() : DateTime(_date.year, _date.month, _date.day, 12);
    try {
      await ExpenseService().add(
        id: _id,
        amount: v,
        category: _category,
        note: _note.text,
        spentAt: spentAt,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('Could not save. Check your internet and try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Add expense'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))],
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: tr('Amount'),
                  prefixText: 'TZS ',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Text(tr('Category'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in kExpenseCategories)
                    ChoiceChip(
                      avatar: Icon(c.icon, size: 18),
                      label: Text(tr(c.label)),
                      selected: _category == c.key,
                      onSelected: (_) => setState(() => _category = c.key),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _note,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('Note (optional)'),
                  border: const OutlineInputBorder(),
                ),
              ),
              Row(
                children: [
                  Text('${tr('Date')}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextButton.icon(
                    onPressed: _busy ? null : _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(DateFormat('d MMM yyyy').format(_date)),
                  ),
                ],
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context, false),
                      child: Text(tr('Cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[900],
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(tr('Save'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';

import '../models/credit.dart';
import '../services/credit_service.dart';

/// Asks for a new customer's name and phone, saves it, and returns it
/// (null if cancelled).
Future<Customer?> askNewCustomer(BuildContext context) {
  return showDialog<Customer>(
    context: context,
    builder: (_) => const _NewCustomerDialog(),
  );
}

/// Bottom sheet to choose who is buying on credit (or add a new customer).
Future<Customer?> pickCustomer(BuildContext context) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _PickerSheet(),
  );
}

class _NewCustomerDialog extends StatefulWidget {
  const _NewCustomerDialog();

  @override
  State<_NewCustomerDialog> createState() => _NewCustomerDialogState();
}

class _NewCustomerDialogState extends State<_NewCustomerDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the customer name');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final c = await CreditService().addCustomer(_name.text, _phone.text);
      if (mounted) Navigator.pop(context, c);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = CreditService.message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New customer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone (optional)',
              hintText: '07XXXXXXXX',
              prefixIcon: Icon(Icons.phone_android),
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
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet();

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  List<Customer> _all = [];
  bool _loading = true;
  String _error = '';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final list = await CreditService().customers();
      if (mounted) setState(() => _all = list);
    } catch (e) {
      if (mounted) setState(() => _error = CreditService.message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addNew() async {
    final c = await askNewCustomer(context);
    if (c != null && mounted) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final c in _all)
        if (q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            (c.phone ?? '').contains(q))
          c
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search customer',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_add)),
                title: const Text('New customer',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: _addNew,
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error.isNotEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error, textAlign: TextAlign.center),
                                  const SizedBox(height: 10),
                                  FilledButton(onPressed: _load, child: const Text('Try again')),
                                ],
                              ),
                            ),
                          )
                        : shown.isEmpty
                            ? const Center(child: Text('No customers yet. Add one above.'))
                            : ListView.builder(
                                itemCount: shown.length,
                                itemBuilder: (_, i) {
                                  final c = shown[i];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      child: Text(c.name.isEmpty
                                          ? '?'
                                          : c.name[0].toUpperCase()),
                                    ),
                                    title: Text(c.name),
                                    subtitle: c.phone == null ? null : Text(c.phone!),
                                    onTap: () => Navigator.pop(context, c),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
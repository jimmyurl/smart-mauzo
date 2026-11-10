import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/credit.dart';
import '../services/app_language.dart';
import '../services/receipt_service.dart';
import '../services/reminder_service.dart';
import '../utils/money.dart';

/// Bottom sheet to remind a customer about their debt on WhatsApp or SMS.
/// The message can be edited before it is sent.
Future<void> showReminderSheet(
  BuildContext context, {
  required Customer customer,
  required double balance,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReminderSheet(customer: customer, balance: balance),
  );
}

class _ReminderSheet extends StatefulWidget {
  final Customer customer;
  final double balance;
  const _ReminderSheet({required this.customer, required this.balance});

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  static const _whatsappGreen = Color(0xFF25D366);

  final _msg = TextEditingController();
  final _pay = TextEditingController();
  bool _swahili = AppLanguage.isSwahili;
  bool _edited = false; // the cashier changed the text by hand
  String _shop = '';
  DateTime? _last;
  String _error = '';

  String? get _number => ReminderService.whatsappNumber(widget.customer.phone);

  @override
  void initState() {
    super.initState();
    _regen();
    _load();
  }

  Future<void> _load() async {
    final shop = await ReceiptService.shopName();
    final pay = await ReminderService.payInfo();
    final last = await ReminderService.lastReminded(widget.customer.id);
    if (!mounted) return;
    setState(() {
      _shop = shop;
      _last = last;
      _pay.text = pay;
    });
    _regen();
  }

  void _regen() {
    if (_edited) return;
    _msg.text = ReminderService.buildMessage(
      swahili: _swahili,
      shopName: _shop.isEmpty ? 'Smart Mauzo' : _shop,
      customerName: widget.customer.name,
      balance: widget.balance,
      payInfo: _pay.text,
    );
  }

  @override
  void dispose() {
    _msg.dispose();
    _pay.dispose();
    super.dispose();
  }

  Future<void> _send({required bool whatsapp}) async {
    final number = _number;
    final text = _msg.text.trim();
    if (number == null || text.isEmpty) return;
    await ReminderService.savePayInfo(_pay.text);
    final ok = whatsapp
        ? await ReminderService.openWhatsApp(number, text)
        : await ReminderService.openSms(number, text);
    if (!mounted) return;
    if (ok) {
      await ReminderService.markReminded(widget.customer.id);
      if (mounted) Navigator.pop(context);
    } else {
      setState(() => _error = tr('Could not open the app'));
    }
  }

  Future<void> _share() async {
    final text = _msg.text.trim();
    if (text.isEmpty) return;
    await ReminderService.savePayInfo(_pay.text);
    await Share.share(text);
    await ReminderService.markReminded(widget.customer.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasNumber = _number != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(widget.customer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                  Text(tzs(widget.balance),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFFC62828))),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _last == null
                    ? tr('No reminder sent yet')
                    : '${tr('Last reminder')}: ${DateFormat('d MMM, HH:mm').format(_last!.toLocal())}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Kiswahili'),
                    selected: _swahili,
                    onSelected: (_) => setState(() {
                      _swahili = true;
                      _edited = false;
                      _regen();
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('English'),
                    selected: !_swahili,
                    onSelected: (_) => setState(() {
                      _swahili = false;
                      _edited = false;
                      _regen();
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _msg,
                maxLines: 5,
                minLines: 3,
                onChanged: (_) => _edited = true,
                decoration: InputDecoration(
                  labelText: tr('Reminder message'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pay,
                maxLength: 60,
                onChanged: (_) => setState(_regen),
                decoration: InputDecoration(
                  labelText: tr('How should they pay? (optional)'),
                  hintText: 'Lipa 5123456 (M-Pesa)',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (!hasNumber)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    tr('Add a phone number to this customer to message them directly.'),
                    style: const TextStyle(color: Color(0xFFEF6C00), fontSize: 12),
                  ),
                ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: hasNumber ? () => _send(whatsapp: true) : null,
                      icon: const Icon(Icons.chat),
                      label: const Text('WhatsApp'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _whatsappGreen,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasNumber ? () => _send(whatsapp: false) : null,
                      icon: const Icon(Icons.sms_outlined),
                      label: const Text('SMS'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.center,
                child: TextButton(onPressed: _share, child: Text(tr('Share...'))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sale.dart';
import '../services/app_language.dart';
import '../utils/money.dart';
import '../utils/payment_style.dart';

/// What the cashier entered for a mobile-money sale paid to the shop's own number.
class MobileMoneyInfo {
  final String provider; // a key of kMobileProviders
  final String? reference; // transaction id from the confirmation SMS (optional)
  const MobileMoneyInfo(this.provider, this.reference);
}

const _kLastProvider = 'sm_last_mobile_provider_v1';

/// Asks which network the customer paid on and (optionally) the transaction
/// reference. Returns null if the cashier cancels. The "I received the SMS" switch
/// must be on before the sale can be saved.
Future<MobileMoneyInfo?> askMobileMoney(BuildContext context, {required double total}) async {
  String? last;
  try {
    last = (await SharedPreferences.getInstance()).getString(_kLastProvider);
  } catch (_) {}
  if (!context.mounted) return null;
  final info = await showModalBottomSheet<MobileMoneyInfo>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MobileMoneySheet(total: total, initial: last),
  );
  if (info != null) {
    try {
      (await SharedPreferences.getInstance()).setString(_kLastProvider, info.provider);
    } catch (_) {}
  }
  return info;
}

class _MobileMoneySheet extends StatefulWidget {
  final double total;
  final String? initial;
  const _MobileMoneySheet({required this.total, this.initial});

  @override
  State<_MobileMoneySheet> createState() => _MobileMoneySheetState();
}

class _MobileMoneySheetState extends State<_MobileMoneySheet> {
  final _ref = TextEditingController();
  String? _provider;
  bool _received = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null && kMobileProviders.containsKey(widget.initial)) {
      _provider = widget.initial;
    }
  }

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  bool get _ready => _provider != null && _received;

  void _save() {
    if (!_ready) return;
    final ref = _ref.text.trim().toUpperCase();
    Navigator.pop(context, MobileMoneyInfo(_provider!, ref.isEmpty ? null : ref));
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: kLipaColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(tr('Mobile money'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(tzs(widget.total),
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold, color: kLipaColor)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr('Ask the customer to pay to your shop number. Check the confirmation SMS on your phone before saving.'),
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
              const SizedBox(height: 14),
              Text(tr('Which network was used?'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in kMobileProviders.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _provider == e.key,
                      onSelected: (_) => setState(() => _provider = e.key),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ref,
                textCapitalization: TextCapitalization.characters,
                maxLength: 20,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
                decoration: InputDecoration(
                  labelText: tr('Transaction reference (optional)'),
                  hintText: 'QJ81XXXXXX',
                  prefixIcon: const Icon(Icons.tag),
                  border: const OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _received,
                onChanged: (v) => setState(() => _received = v),
                title: Text(tr('I received the payment confirmation SMS'),
                    style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('Cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _ready ? _save : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kLipaColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(tr('Save sale'),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
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
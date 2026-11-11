import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/business_type.dart';
import '../services/app_language.dart';
import '../services/offline_store.dart';
import '../services/shop_settings.dart';

/// The four business types as tappable cards.
class BusinessTypePicker extends StatelessWidget {
  final BusinessType? selected;
  final ValueChanged<BusinessType> onChanged;
  const BusinessTypePicker({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final blue = Colors.blue[900]!;
    return Column(
      children: [
        for (final i in kBusinessTypes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onChanged(i.type),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: selected == i.type ? Colors.blue[50] : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected == i.type ? blue : Colors.grey.shade300,
                    width: selected == i.type ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(i.icon, size: 28, color: blue),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(i.label),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(tr(i.description),
                              style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        ],
                      ),
                    ),
                    if (selected == i.type) Icon(Icons.check_circle, color: blue),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Bottom sheet to choose (or change) the business type. Returns the choice, or
/// null if the person closed it without choosing.
Future<BusinessType?> showBusinessTypeSheet(
  BuildContext context, {
  BusinessType? current,
  bool allowSkip = false,
}) {
  return showModalBottomSheet<BusinessType>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _BusinessTypeSheet(current: current, allowSkip: allowSkip),
  );
}

class _BusinessTypeSheet extends StatefulWidget {
  final BusinessType? current;
  final bool allowSkip;
  const _BusinessTypeSheet({required this.current, required this.allowSkip});

  @override
  State<_BusinessTypeSheet> createState() => _BusinessTypeSheetState();
}

class _BusinessTypeSheetState extends State<_BusinessTypeSheet> {
  BusinessType? _choice;

  @override
  void initState() {
    super.initState();
    _choice = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('What kind of business do you run?'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              tr('We use this to suggest product categories and shortcuts. You can change it later in Profile.'),
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 14),
            BusinessTypePicker(selected: _choice, onChanged: (t) => setState(() => _choice = t)),
            const SizedBox(height: 6),
            Row(
              children: [
                if (widget.allowSkip)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('Later')),
                    ),
                  ),
                if (widget.allowSkip) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _choice == null ? null : () => Navigator.pop(context, _choice),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[900],
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(tr('Save'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _kSnooze = 'sm_business_type_ask_until_v1';
bool _askedThisRun = false;

/// Owners of a shop with no business type yet (shops made before this feature)
/// are asked once per app start; "Later" waits 3 days.
Future<void> maybeAskBusinessType(BuildContext context) async {
  if (_askedThisRun || !OfflineIdentity.isOwner) return;
  await ShopSettings.load();
  if (!ShopSettings.serverSaysUnset || ShopSettings.type.value != null) return;
  try {
    final v = (await SharedPreferences.getInstance()).getString(_kSnooze);
    final until = v == null ? null : DateTime.tryParse(v);
    if (until != null && until.isAfter(DateTime.now())) return;
  } catch (_) {}
  if (!context.mounted) return;
  _askedThisRun = true;

  final chosen = await showBusinessTypeSheet(context, allowSkip: true);
  if (chosen == null) {
    try {
      await (await SharedPreferences.getInstance()).setString(
          _kSnooze, DateTime.now().add(const Duration(days: 3)).toIso8601String());
    } catch (_) {}
    return;
  }
  try {
    await ShopSettings.setBusinessType(chosen);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Could not save. Check your internet and try again.'))));
  }
}

/// Profile row: shows the current business type and lets the owner change it.
class BusinessTypeTile extends StatelessWidget {
  const BusinessTypeTile({super.key});

  Future<void> _change(BuildContext context, BusinessType? current) async {
    final chosen = await showBusinessTypeSheet(context, current: current);
    if (chosen == null || chosen == current || !context.mounted) return;
    try {
      await ShopSettings.setBusinessType(chosen);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Business type saved'))));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Could not save. Check your internet and try again.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessType?>(
      valueListenable: ShopSettings.type,
      builder: (context, type, _) {
        final info = type == null ? null : businessInfo(type);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(info?.icon ?? Icons.storefront_outlined, color: Colors.blue[900]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Business type'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(info == null ? tr('Not set') : tr(info.label),
                        style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ],
                ),
              ),
              TextButton(onPressed: () => _change(context, type), child: Text(tr('Change'))),
            ],
          ),
        );
      },
    );
  }
}
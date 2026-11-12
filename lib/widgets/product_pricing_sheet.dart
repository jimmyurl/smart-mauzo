import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/product_unit.dart';
import '../services/app_language.dart';
import '../services/supabase_service.dart';
import '../utils/money.dart';

/// Owner only: edit a product's name and prices (retail, buying, wholesale, special),
/// what one item is called, and its bigger pack units. Returns true if saved.
Future<bool?> showProductPricingSheet(BuildContext context, Product product) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PricingSheet(product: product),
  );
}

double? _parse(String s) {
  final t = s.replaceAll(',', '').trim();
  return t.isEmpty ? null : double.tryParse(t);
}

String _plain(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

class _PricingSheet extends StatefulWidget {
  final Product product;
  const _PricingSheet({required this.product});

  @override
  State<_PricingSheet> createState() => _PricingSheetState();
}

class _PricingSheetState extends State<_PricingSheet> {
  late final TextEditingController _title = TextEditingController(text: widget.product.title);
  late final TextEditingController _retail =
      TextEditingController(text: _plain(widget.product.price));
  late final TextEditingController _buying = TextEditingController(
      text: widget.product.buyingPrice > 0 ? _plain(widget.product.buyingPrice) : '');
  late final TextEditingController _wholesale = TextEditingController(
      text: widget.product.priceWholesale == null ? '' : _plain(widget.product.priceWholesale!));
  late final TextEditingController _special = TextEditingController(
      text: widget.product.priceSpecial == null ? '' : _plain(widget.product.priceSpecial!));
  late final TextEditingController _baseUnit =
      TextEditingController(text: widget.product.baseUnit ?? '');

  late final List<ProductUnit> _units = List<ProductUnit>.of(widget.product.units);
  final List<String> _removed = [];
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    for (final c in [_title, _retail, _buying, _wholesale, _special, _baseUnit]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _baseName => _baseUnit.text.trim().isEmpty ? tr('piece') : _baseUnit.text.trim();

  InputDecoration _dec(String label, {String? prefix, String? hint}) => InputDecoration(
        labelText: label,
        prefixText: prefix,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      );

  Widget _money(TextEditingController c, String label, {String? hint}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: _dec(label, prefix: 'TZS ', hint: hint),
      );

  Future<void> _editUnit(ProductUnit? existing) async {
    final result = await showDialog<ProductUnit>(
      context: context,
      builder: (_) => _UnitDialog(
        productId: widget.product.id,
        existing: existing,
        baseName: _baseName,
        takenNames: [
          for (final u in _units)
            if (u.id != existing?.id) u.name.toLowerCase(),
        ],
      ),
    );
    if (result == null) return;
    setState(() {
      final i = _units.indexWhere((u) => u.id == result.id);
      if (i >= 0) {
        _units[i] = result;
      } else {
        _units.add(result);
      }
    });
  }

  void _removeUnit(ProductUnit u) {
    setState(() {
      _units.removeWhere((x) => x.id == u.id);
      if (widget.product.units.any((x) => x.id == u.id)) _removed.add(u.id);
    });
  }

  Future<void> _save() async {
    String? fail;
    final title = _title.text.trim();
    final retail = _parse(_retail.text);
    final buying = _parse(_buying.text) ?? 0;
    final wholesale = _parse(_wholesale.text);
    final special = _parse(_special.text);

    if (title.isEmpty) {
      fail = tr('Missing name');
    } else if (retail == null || retail <= 0) {
      fail = tr('Enter a valid price');
    } else if (buying < 0) {
      fail = tr('Enter a valid price');
    } else if (_wholesale.text.trim().isNotEmpty && (wholesale == null || wholesale <= 0)) {
      fail = tr('Enter a valid price');
    } else if (_special.text.trim().isNotEmpty && (special == null || special <= 0)) {
      fail = tr('Enter a valid price');
    }
    if (fail != null) {
      setState(() => _error = fail!);
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final svc = SupabaseService();
      await svc.updateProductPricing(
        widget.product.id,
        title: title,
        price: retail!,
        buyingPrice: buying,
        priceWholesale: wholesale,
        priceSpecial: special,
        baseUnit: _baseUnit.text,
      );
      await svc.saveProductUnits(_units, _removed);
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.code == '23505'
            ? tr('This pack name is already used')
            : tr('Could not save. Check your internet and try again.');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = tr('Could not save. Check your internet and try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final retail = _parse(_retail.text) ?? widget.product.price;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Edit prices & units'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            TextField(controller: _title, decoration: _dec(tr('Product name'))),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _money(_retail, tr('Retail price'))),
                const SizedBox(width: 10),
                Expanded(child: _money(_buying, tr('Buying price'))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _money(_wholesale, tr('Wholesale price'))),
                const SizedBox(width: 10),
                Expanded(child: _money(_special, tr('Special price (e.g. contractor)'))),
              ],
            ),
            const SizedBox(height: 4),
            Text(tr('Leave a price empty to use the retail price.'),
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 14),
            TextField(
              controller: _baseUnit,
              maxLength: 30,
              onChanged: (_) => setState(() {}),
              decoration: _dec(tr('Unit name (e.g. tablet, bag)')),
            ),
            const SizedBox(height: 4),
            Text(tr('Pack units'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              tr('Stock is counted in the unit above. A pack unit is a bigger unit that holds several of it.'),
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 6),
            for (final u in _units)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  dense: true,
                  title: Text('${u.name} = ${u.factor} $_baseName',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${tzs(u.priceFor('retail', retail))}'
                    '${u.priceWholesale == null ? '' : '  •  ${tr('Wholesale')} ${tzs(u.priceWholesale!)}'}'
                    '${u.priceSpecial == null ? '' : '  •  ${tr('Special')} ${tzs(u.priceSpecial!)}'}',
                  ),
                  onTap: () => _editUnit(u),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: tr('Remove'),
                    onPressed: () => _removeUnit(u),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _editUnit(null),
                icon: const Icon(Icons.add),
                label: Text(tr('Add a pack unit')),
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
    );
  }
}

class _UnitDialog extends StatefulWidget {
  final String productId;
  final ProductUnit? existing;
  final String baseName;
  final List<String> takenNames;
  const _UnitDialog({
    required this.productId,
    required this.existing,
    required this.baseName,
    required this.takenNames,
  });

  @override
  State<_UnitDialog> createState() => _UnitDialogState();
}

class _UnitDialogState extends State<_UnitDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _size =
      TextEditingController(text: widget.existing == null ? '' : '${widget.existing!.factor}');
  late final TextEditingController _price = TextEditingController(
      text: widget.existing?.price == null ? '' : _plain(widget.existing!.price!));
  late final TextEditingController _wholesale = TextEditingController(
      text: widget.existing?.priceWholesale == null ? '' : _plain(widget.existing!.priceWholesale!));
  late final TextEditingController _special = TextEditingController(
      text: widget.existing?.priceSpecial == null ? '' : _plain(widget.existing!.priceSpecial!));
  String _error = '';

  @override
  void dispose() {
    for (final c in [_name, _size, _price, _wholesale, _special]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _money(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: label,
            prefixText: 'TZS ',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  bool _badPrice(TextEditingController c) {
    if (c.text.trim().isEmpty) return false;
    final v = _parse(c.text);
    return v == null || v <= 0;
  }

  void _ok() {
    final name = _name.text.trim();
    final size = int.tryParse(_size.text.trim());
    if (name.isEmpty || name.length > 30) {
      setState(() => _error = tr('Missing name'));
    } else if (widget.takenNames.contains(name.toLowerCase())) {
      setState(() => _error = tr('This pack name is already used'));
    } else if (size == null || size < 2) {
      setState(() => _error = tr('Pack size must be 2 or more'));
    } else if (_badPrice(_price) || _badPrice(_wholesale) || _badPrice(_special)) {
      setState(() => _error = tr('Enter a valid price'));
    } else {
      Navigator.pop(
        context,
        ProductUnit(
          id: widget.existing?.id ?? const Uuid().v4(),
          productId: widget.productId,
          name: name,
          factor: size,
          price: _parse(_price.text),
          priceWholesale: _parse(_wholesale.text),
          priceSpecial: _parse(_special.text),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Add a pack unit')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              maxLength: 30,
              decoration: InputDecoration(
                labelText: tr('Pack name (e.g. strip, box)'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _size,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '${tr('How many')} ${widget.baseName} ${tr('in one pack?')}',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            _money(_price, tr('Retail price of one pack (empty = retail price x size)')),
            _money(_wholesale, tr('Wholesale price')),
            _money(_special, tr('Special price (e.g. contractor)')),
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
        FilledButton(onPressed: _ok, child: Text(tr('OK'))),
      ],
    );
  }
}
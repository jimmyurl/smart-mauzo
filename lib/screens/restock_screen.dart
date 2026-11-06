import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/supabase_service.dart';
import '../utils/money.dart';

/// Add stock bought from a supplier: quantity, buying price per unit, supplier.
/// Returns true when the restock was saved.
class RestockScreen extends StatefulWidget {
  final Product product;
  final List<String> knownSuppliers;
  const RestockScreen({
    super.key,
    required this.product,
    this.knownSuppliers = const [],
  });

  @override
  State<RestockScreen> createState() => _RestockScreenState();
}

class _RestockScreenState extends State<RestockScreen> {
  final _svc = SupabaseService();
  final _qty = TextEditingController();
  late final TextEditingController _cost;
  final _supplier = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.product.buyingPrice;
    _cost = TextEditingController(text: c > 0 ? c.toStringAsFixed(0) : '');
    for (final c in [_qty, _cost]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_qty, _cost, _supplier, _phone, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _q => int.tryParse(_qty.text.trim()) ?? 0;
  double get _c => double.tryParse(_cost.text.trim().replaceAll(',', '')) ?? 0;

  Future<void> _save() async {
    if (_q <= 0) return _snack('Enter how many items you received');
    if (_c <= 0) return _snack('Enter the buying price per item');
    setState(() => _saving = true);
    final error = await _svc.restockProduct(
      productId: widget.product.id,
      quantity: _q,
      buyingPrice: _c,
      supplierName: _supplier.text.trim(),
      supplierPhone: _phone.text.trim(),
      note: _note.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) return _snack(error);
    Navigator.pop(context, true);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final margin = p.price - _c;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add stock'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(p.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('In stock now: ${p.stockQuantity}  •  Selling price: ${tzs(p.price)}',
              style: TextStyle(color: Colors.grey[700])),
          const SizedBox(height: 20),
          TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Quantity received', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cost,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Buying price (per item)',
                prefixText: 'TZS ',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Autocomplete<String>(
            optionsBuilder: (v) => widget.knownSuppliers.where(
                (s) => s.toLowerCase().contains(v.text.toLowerCase())),
            onSelected: (v) => _supplier.text = v,
            fieldViewBuilder: (ctx, ctrl, focus, _) {
              ctrl.addListener(() => _supplier.text = ctrl.text);
              return TextField(
                controller: ctrl,
                focusNode: focus,
                decoration: const InputDecoration(
                    labelText: 'Supplier (optional)',
                    border: OutlineInputBorder()),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Supplier phone (optional)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
                labelText: 'Note (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          if (_q > 0 && _c > 0)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total cost: ${tzs(_q * _c)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('New stock: ${p.stockQuantity + _q}'),
                  Text(
                    'Profit per item: ${tzs(margin)}',
                    style: TextStyle(
                        color: margin < 0 ? Colors.red : Colors.green[800]),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.add_box),
              label: Text(_saving ? 'Saving...' : 'Save stock'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[900],
                  foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
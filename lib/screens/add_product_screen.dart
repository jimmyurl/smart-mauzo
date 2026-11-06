import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/shop_service.dart';
import '../services/supabase_service.dart';
import '../utils/money.dart';
import 'barcode_scan_page.dart';

/// Register a new item (product) in the shop. Owner only.
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _barcode = TextEditingController();
  final _buyPrice = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final _description = TextEditingController();
  final _nameFocus = FocusNode();
  final _svc = SupabaseService();

  bool _saving = false;
  bool? _isOwner; // null while we check

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _buyPrice.dispose();
    _price.dispose();
    _stock.dispose();
    _description.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _checkRole() async {
    try {
      final shop = await ShopService().myShop();
      if (mounted) setState(() => _isOwner = shop?.isOwner ?? false);
    } catch (_) {
      // Offline or error: let the server decide when saving.
      if (mounted) setState(() => _isOwner = true);
    }
  }

  void _msg(String text, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: ok ? Colors.green : null),
    );
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
    );
    if (code != null && code.isNotEmpty) setState(() => _barcode.text = code);
  }

  void _clear() {
    _name.clear();
    _barcode.clear();
    _buyPrice.clear();
    _price.clear();
    _stock.clear();
    _description.clear();
    _formKey.currentState?.reset();
    _nameFocus.requestFocus();
  }

  Future<void> _save({required bool addAnother}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final title = _name.text.trim();
    try {
      await _svc.addProduct(
        title: title,
        buyingPrice: double.parse(_buyPrice.text),
        price: double.parse(_price.text),
        stock: int.parse(_stock.text),
        barcode: _barcode.text.trim(),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      );
      if (!mounted) return;
      _msg('"$title" registered', ok: true);
      if (addAnother) {
        _clear();
      } else {
        Navigator.pop(context, true);
      }
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        _msg('An item with this barcode already exists in your shop.');
      } else if (e.code == '42501') {
        _msg('Only the shop owner can register items.');
      } else {
        _msg(e.message);
      }
    } catch (_) {
      _msg('Could not save. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Shows the profit per item as soon as both prices are typed.
  Widget _profitPreview() {
    return AnimatedBuilder(
      animation: Listenable.merge([_buyPrice, _price]),
      builder: (context, _) {
        final buy = double.tryParse(_buyPrice.text);
        final sell = double.tryParse(_price.text);
        if (buy == null || sell == null || buy <= 0 || sell <= 0) {
          return const SizedBox.shrink();
        }
        final profit = sell - buy;
        final margin = profit / sell * 100;
        final loss = profit < 0;
        final color = loss ? Colors.red[700]! : Colors.green[700]!;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            loss
                ? 'Selling below buying price: you lose ${tzs(-profit)} on each item.'
                : 'Profit per item: ${tzs(profit)}  •  Margin ${margin.toStringAsFixed(1)}%',
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final blue = Colors.blue[900]!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register item'),
        backgroundColor: blue,
        foregroundColor: Colors.white,
      ),
      body: _isOwner == null
          ? const Center(child: CircularProgressIndicator())
          : _isOwner == false
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline, size: 48),
                        const SizedBox(height: 12),
                        const Text('Only the shop owner can register items.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        OutlinedButton(
                            onPressed: () => Navigator.pop(context), child: const Text('Back')),
                      ],
                    ),
                  ),
                )
              : AbsorbPointer(
                  absorbing: _saving,
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        TextFormField(
                          controller: _name,
                          focusNode: _nameFocus,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Item name *',
                            hintText: 'e.g. Sugar 1kg',
                            prefixIcon: Icon(Icons.label_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().length < 2)
                              ? 'Please enter the item name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _barcode,
                          decoration: InputDecoration(
                            labelText: 'Barcode (optional)',
                            helperText: 'Scan it, type it, or leave empty if the item has none',
                            prefixIcon: const Icon(Icons.qr_code),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.qr_code_scanner),
                              tooltip: 'Scan barcode',
                              onPressed: _scanBarcode,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _buyPrice,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: const InputDecoration(
                                  labelText: 'Buying price (TZS) *',
                                  helperText: 'Cost of 1 item',
                                  prefixIcon: Icon(Icons.shopping_cart_outlined),
                                  border: OutlineInputBorder(),
                                ),
                                validator: (v) {
                                  final n = double.tryParse(v ?? '');
                                  return (n == null || n <= 0) ? 'Enter buying price' : null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _price,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: const InputDecoration(
                                  labelText: 'Selling price (TZS) *',
                                  helperText: 'Price to customer',
                                  prefixIcon: Icon(Icons.payments_outlined),
                                  border: OutlineInputBorder(),
                                ),
                                validator: (v) {
                                  final n = double.tryParse(v ?? '');
                                  return (n == null || n <= 0) ? 'Enter selling price' : null;
                                },
                              ),
                            ),
                          ],
                        ),
                        _profitPreview(),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _stock,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            labelText: 'In stock *',
                            prefixIcon: Icon(Icons.inventory_2_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              int.tryParse(v ?? '') == null ? 'Enter quantity' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _description,
                          maxLines: 2,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Notes (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: () => _save(addAnother: false),
                            icon: const Icon(Icons.check),
                            label: const Text('Save item',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: () => _save(addAnother: true),
                            icon: const Icon(Icons.add),
                            label: const Text('Save & add another'),
                          ),
                        ),
                        if (_saving)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
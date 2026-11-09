import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/product.dart';
import '../services/receipt_service.dart';
import '../services/supabase_service.dart';
import '../services/app_language.dart';

/// A product is "low" at this many items or fewer (same level as the rest of the app).
const int kLowStockLevel = 5;

/// How many days ahead an expiry date counts as "soon".
const int kExpirySoonDays = 30;

/// Owner screen with two tabs:
///  * Reorder: low and finished products, grouped by the supplier they were last
///    bought from, with a ready-to-send order message for each supplier.
///  * Expiry: products that are expired or expire soon.
class StockAlertsScreen extends StatefulWidget {
  final int initialTab;
  const StockAlertsScreen({super.key, this.initialTab = 0});

  @override
  State<StockAlertsScreen> createState() => _StockAlertsScreenState();
}

class _Supplier {
  final String name; // '' = no supplier recorded yet
  final String? phone;
  final List<Product> items = [];
  _Supplier(this.name, this.phone);
}

class _StockAlertsScreenState extends State<StockAlertsScreen> {
  static const _navy = Color(0xFF0D47A1);
  static const _noSupplier = '';

  final SupabaseService _api = SupabaseService();

  List<Product> _products = [];
  // newest purchase per product id
  final Map<String, Map<String, dynamic>> _lastPurchase = {};
  // quantities the owner changed by hand
  final Map<String, int> _qty = {};

  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final products = await _api.getProducts();
      final purchases = await _api.getStockPurchases(); // newest first
      final last = <String, Map<String, dynamic>>{};
      for (final r in purchases) {
        final id = r['product_id']?.toString();
        if (id != null) last.putIfAbsent(id, () => r);
      }
      if (!mounted) return;
      setState(() {
        _products = products;
        _lastPurchase
          ..clear()
          ..addAll(last);
        _error = '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendly(e);
        _loading = false;
      });
    }
  }

  // ------------------------------------------------------------ reorder data

  Map<String, dynamic>? _supplierRow(Product p) {
    final s = _lastPurchase[p.id]?['sm_suppliers'];
    return s is Map ? Map<String, dynamic>.from(s) : null;
  }

  int? _lastQty(Product p) => (_lastPurchase[p.id]?['quantity'] as num?)?.toInt();

  int _orderQty(Product p) => _qty[p.id] ?? _lastQty(p) ?? 10;

  List<_Supplier> _groups() {
    final low = _products.where((p) => p.stockQuantity <= kLowStockLevel).toList()
      ..sort((a, b) {
        final c = a.stockQuantity.compareTo(b.stockQuantity);
        return c != 0 ? c : a.title.compareTo(b.title);
      });
    final byName = <String, _Supplier>{};
    for (final p in low) {
      final s = _supplierRow(p);
      final name = (s?['name'] as String?)?.trim() ?? _noSupplier;
      final g = byName.putIfAbsent(name, () => _Supplier(name, s?['phone'] as String?));
      g.items.add(p);
    }
    final list = byName.values.toList()
      ..sort((a, b) {
        if (a.name == _noSupplier) return 1;
        if (b.name == _noSupplier) return -1;
        return a.name.compareTo(b.name);
      });
    return list;
  }

  Future<void> _copyOrder(_Supplier g) async {
    String shop = '';
    try {
      shop = await ReceiptService.shopName();
    } catch (_) {}
    final b = StringBuffer(g.name.isEmpty ? 'Hello, ' : 'Hello ${g.name}, ')
      ..writeln('I would like to order:');
    for (final p in g.items) {
      b.writeln('- ${p.title} x ${_orderQty(p)}');
    }
    if (shop.isNotEmpty) b.write('\nThank you, $shop');
    await Clipboard.setData(ClipboardData(text: b.toString().trimRight()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(tr('Order copied. Paste it in WhatsApp or SMS.')),
        backgroundColor: Colors.green,
      ));
  }

  Future<void> _editQty(Product p) async {
    final c = TextEditingController(text: '${_orderQty(p)}');
    final v = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Order of ${p.title}'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('Quantity to order')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Cancel'))),
          TextButton(
            onPressed: () {
              final n = int.tryParse(c.text.trim());
              if (n != null && n > 0) Navigator.pop(d, n);
            },
            child: Text(tr('OK')),
          ),
        ],
      ),
    );
    if (v != null && mounted) setState(() => _qty[p.id] = v);
  }

  // ------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab.clamp(0, 1),
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Stock alerts')),
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [Tab(text: tr('Reorder')), Tab(text: tr('Expiry'))],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: Text(tr('Try again'))),
                        ],
                      ),
                    ),
                  )
                : TabBarView(children: [_reorderTab(), _expiryTab()]),
      ),
    );
  }

  Widget _reorderTab() {
    final groups = _groups();
    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(tr('Nothing to reorder. Every product has more than 5 in stock.'),
              textAlign: TextAlign.center),
        ),
      );
    }
    final count = groups.fold<int>(0, (s, g) => s + g.items.length);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('$count product${count == 1 ? '' : 's'} at $kLowStockLevel or fewer. '
              'Tap a quantity to change it, then copy the order for each supplier.',
              style: TextStyle(color: Colors.grey[700], fontSize: 12)),
          const SizedBox(height: 12),
          for (final g in groups) _supplierCard(g),
        ],
      ),
    );
  }

  Widget _supplierCard(_Supplier g) {
    final none = g.name == _noSupplier;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, color: _navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(none ? 'No supplier recorded yet' : g.name,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      if (g.phone != null && g.phone!.isNotEmpty)
                        Text(g.phone!, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _copyOrder(g),
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(tr('Copy order')),
                ),
              ],
            ),
            const Divider(height: 12),
            for (final p in g.items) _reorderRow(p),
          ],
        ),
      ),
    );
  }

  Widget _reorderRow(Product p) {
    final out = p.stockQuantity <= 0;
    final lastQ = _lastQty(p);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${out ? tr('Out of stock') : '${tr('In stock')}: ${p.stockQuantity}'}'
        '${lastQ == null ? '' : '  •  last bought $lastQ'}',
        style: TextStyle(color: out ? Colors.red : Colors.orange[800]),
      ),
      trailing: OutlinedButton(
        onPressed: () => _editQty(p),
        child: Text('Order ${_orderQty(p)}'),
      ),
    );
  }

  // ----------------------------------------------------------------- expiry

  Widget _expiryTab() {
    final withDate = _products.where((p) => p.expiryDate != null).toList();
    // only things still on the shelf matter
    final alerts = withDate
        .where((p) => p.stockQuantity > 0 && (p.daysToExpiry ?? 9999) <= kExpirySoonDays)
        .toList()
      ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));

    if (withDate.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No expiry dates yet.\nOpen a product in Products and choose "Set expiry".',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (alerts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nothing expires in the next $kExpirySoonDays days.\n'
            '${withDate.length} product${withDate.length == 1 ? ' has' : 's have'} an expiry date.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final expired = alerts.where((p) => p.daysToExpiry! < 0).toList();
    final soon = alerts.where((p) => p.daysToExpiry! >= 0).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (expired.isNotEmpty) ...[
            _sectionTitle('Expired (${expired.length})', Colors.red),
            for (final p in expired) _expiryRow(p),
            const SizedBox(height: 12),
          ],
          if (soon.isNotEmpty) ...[
            _sectionTitle('Expiring within $kExpirySoonDays days (${soon.length})',
                Colors.orange[800]!),
            for (final p in soon) _expiryRow(p),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      );

  Widget _expiryRow(Product p) {
    final d = p.daysToExpiry!;
    final color = d < 0 ? Colors.red : Colors.orange[800]!;
    final when = d < 0
        ? 'Expired ${-d} day${d == -1 ? '' : 's'} ago'
        : d == 0
            ? tr('Expires today')
            : 'Expires in $d day${d == 1 ? '' : 's'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(Icons.event_busy, color: color),
        ),
        title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$when  •  ${DateFormat('d MMM yyyy').format(p.expiryDate!)}\n'
          '${p.stockQuantity} in stock',
          style: TextStyle(color: color),
        ),
        isThreeLine: true,
      ),
    );
  }
}
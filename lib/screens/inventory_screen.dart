import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../services/offline_store.dart';
import '../services/shop_settings.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../utils/category_utils.dart';
import '../utils/money.dart';
import '../widgets/category_chips.dart';
import '../widgets/category_field.dart';
import 'add_product_screen.dart';
import 'restock_screen.dart';
import 'stock_alerts_screen.dart';
import '../services/app_language.dart';

/// Products: grouped by category, searchable, update stock, register new items.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

/// One line of the flattened list: either a category header or a product.
class _Row {
  final String? category;
  final List<Product>? group;
  final Product? product;
  const _Row.header(this.category, this.group) : product = null;
  const _Row.item(this.product)
      : category = null,
        group = null;
  bool get isHeader => product == null;
}

class _InventoryScreenState extends State<InventoryScreen> {
  static const int _lowStock = 5;

  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _search = TextEditingController();
  List<Product> _products = [];
  String _query = '';
  String? _category; // null = All
  final Set<String> _expanded = {};
  bool _isLoading = true;
  String? _error;
  bool _fromCache = false; // showing the list saved on this phone

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadInventory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final load = await _supabaseService.getProductsOrCached();
      // Sales still waiting to sync already left the shelf: show the lower stock.
      final products = SyncService().applyPending(load.products);
      if (!mounted) return;
      setState(() {
        _fromCache = load.fromCache;
        _products = products;
        _isLoading = false;
        if (_category != null && !products.any((p) => categoryOf(p) == _category)) {
          _category = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = friendly(e);
      });
    }
  }

  bool get _searching => _query.trim().isNotEmpty;

  List<_Row> _buildRows() {
    final q = _query.trim().toLowerCase();
    Iterable<Product> list = _products;
    if (_category != null) list = list.where((p) => categoryOf(p) == _category);
    if (q.isNotEmpty) {
      list = list.where((p) => p.title.toLowerCase().contains(q) || p.barcode.contains(q));
    }
    final rows = <_Row>[];
    final showHeaders = _category == null;
    final showAllItems = _searching || _category != null;
    groupByCategory(list).forEach((cat, items) {
      if (showHeaders) rows.add(_Row.header(cat, items));
      if (showAllItems || _expanded.contains(cat)) {
        rows.addAll(items.map((p) => _Row.item(p)));
      }
    });
    return rows;
  }

  /// Changing products needs the live server, so it is blocked while the list on
  /// screen is the saved copy. Returns true (after telling the user) when blocked.
  bool _needsInternet() {
    if (!_fromCache) return false;
    _msg('You are offline. Connect to the internet to change products.');
    return true;
  }

  void _msg(String text, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: ok ? Colors.green : null),
    );
  }

  Future<void> _updateStock(Product product, int newQuantity) async {
    final ok = await _supabaseService.updateProductStock(product.id, newQuantity);
    if (!mounted) return;
    if (ok) {
      _msg('Stock updated', ok: true);
      _loadInventory();
    } else {
      _msg('Could not update stock (only the shop owner can do this)');
    }
  }

  Future<void> _setCategory(Product product, String category) async {
    final ok = await _supabaseService.updateProductCategory(product.id, category);
    if (!mounted) return;
    if (ok) {
      _msg('Category updated', ok: true);
      _loadInventory();
    } else {
      _msg('Could not update category (only the shop owner can do this)');
    }
  }

  Future<void> _openAlerts() async {
    if (_needsInternet()) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StockAlertsScreen()),
    );
    if (mounted) _loadInventory();
  }

  /// Short note shown under a product that has expired or expires soon.
  String _expiryNote(Product p) {
    final d = p.daysToExpiry;
    if (d == null || p.stockQuantity <= 0) return '';
    if (d < 0) return '  •  EXPIRED';
    if (d <= 30) return '  •  expires in $d day${d == 1 ? '' : 's'}';
    return '';
  }

  Future<void> _editExpiry(Product product) async {
    if (_needsInternet()) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = today.subtract(const Duration(days: 365));
    final current = product.expiryDate;
    final picked = await showDatePicker(
      context: context,
      helpText: 'Expiry date of ${product.title}',
      initialDate: (current != null && !current.isBefore(first))
          ? current
          : today.add(const Duration(days: 30)),
      firstDate: first,
      lastDate: today.add(const Duration(days: 3650)),
    );
    if (picked == null) return;
    final ok = await _supabaseService.updateProductExpiry(product.id, picked);
    if (!mounted) return;
    if (ok) {
      _msg('Expiry date saved', ok: true);
      _loadInventory();
    } else {
      _msg('Could not save the expiry date. Has the stock_alerts.sql file been run? (Only the owner can do this.)');
    }
  }

  Future<void> _clearExpiry(Product product) async {
    if (_needsInternet()) return;
    final ok = await _supabaseService.updateProductExpiry(product.id, null);
    if (!mounted) return;
    if (ok) {
      _msg('Expiry date removed', ok: true);
      _loadInventory();
    } else {
      _msg('Could not remove the expiry date');
    }
  }

  Future<void> _openRestock(Product product) async {
    if (_needsInternet()) return;
    final suppliers = await _supabaseService.getSupplierNames();
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RestockScreen(product: product, knownSuppliers: suppliers),
      ),
    );
    if (saved == true) {
      _msg('Stock added', ok: true);
      _loadInventory();
    }
  }

  Future<void> _openAddProduct() async {
    if (_needsInternet()) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddProductScreen()),
    );
    if (mounted) _loadInventory();
  }

  Color _stockColor(int qty) {
    if (qty <= 0) return Colors.red;
    if (qty <= _lowStock) return Colors.orange;
    return Colors.green;
  }

  void _toggleAll() {
    final all = groupByCategory(_products).keys.toSet();
    setState(() {
      if (_expanded.length >= all.length) {
        _expanded.clear();
      } else {
        _expanded
          ..clear()
          ..addAll(all);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupByCategory(_products);
    final counts = {for (final e in groups.entries) e.key: e.value.length};
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Products')),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        actions: [
          if (OfflineIdentity.isOwner)
            IconButton(
              icon: const Icon(Icons.notifications_active_outlined),
              tooltip: 'Reorder list & expiry',
              onPressed: _openAlerts,
            ),
          if (_category == null && !_searching)
            IconButton(
              icon: Icon(_expanded.length >= groups.length
                  ? Icons.unfold_less
                  : Icons.unfold_more),
              tooltip: 'Expand / collapse all',
              onPressed: _toggleAll,
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadInventory),
        ],
      ),
      body: Column(
        children: [
          if (_fromCache)
            Container(
              width: double.infinity,
              color: Colors.orange[100],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, size: 18, color: Colors.orange[900]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No internet. Showing the list saved on this phone. You can look and search, but not change anything. Tap refresh when you are back online.',
                      style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search by name or barcode',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (!_isLoading && _products.isNotEmpty)
            CategoryChips(
              counts: counts,
              total: _products.length,
              selected: _category,
              onSelected: (c) => setState(() => _category = c),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddProduct,
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadInventory, child: Text(tr('Retry'))),
            ],
          ),
        ),
      );
    }
    final rows = _buildRows();
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _products.isEmpty
                ? 'No items yet.\nTap "Add item" to register your first product.'
                : 'No items match your search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadInventory,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          return row.isHeader ? _buildHeader(row) : _buildItem(row.product!);
        },
      ),
    );
  }

  Widget _buildHeader(_Row row) {
    final items = row.group!;
    final low = items.where((p) => p.stockQuantity <= _lowStock).length;
    final collapsible = !_searching;
    final open = !collapsible || _expanded.contains(row.category);
    return InkWell(
      onTap: collapsible
          ? () => setState(() {
                if (!_expanded.remove(row.category)) _expanded.add(row.category!);
              })
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, color: Colors.blue[900]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                row.category!,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: Colors.blue[900]),
              ),
            ),
            if (low > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('$low low',
                    style: const TextStyle(color: Colors.orange, fontSize: 12)),
              ),
            Text('${items.length} items', style: TextStyle(color: Colors.grey[600])),
            if (collapsible) Icon(open ? Icons.expand_less : Icons.expand_more),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(Product product) {
    final color = _stockColor(product.stockQuantity);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: () => _showProductDetails(product),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(Icons.inventory_2_outlined, color: color),
        ),
        title: Text(product.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${tzs(product.price)}  •  ${product.stockQuantity} in stock'
          '${product.stockQuantity <= 0 ? '  (out of stock)' : product.stockQuantity <= _lowStock ? '  (low)' : ''}'
          '${_expiryNote(product)}',
          style: TextStyle(color: color),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.add_box_outlined),
              tooltip: 'Add stock from supplier',
              onPressed: () => _openRestock(product),
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Correct stock count',
              onPressed: () => _showUpdateStockDialog(product),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUpdateStockDialog(Product product) {
    if (_needsInternet()) return Future<void>.value();
    final controller = TextEditingController(text: product.stockQuantity.toString());
    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Update ${product.title} stock'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'New stock quantity'),
        ),
        actions: [
          TextButton(
            child: Text(tr('Cancel')),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          TextButton(
            child: const Text('Update'),
            onPressed: () {
              final newQuantity = int.tryParse(controller.text);
              if (newQuantity != null && newQuantity >= 0) {
                Navigator.pop(dialogContext);
                _updateStock(product, newQuantity);
              } else {
                _msg('Please enter a valid quantity');
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showChangeCategoryDialog(Product product) {
    if (_needsInternet()) return Future<void>.value();
    final current = categoryOf(product);
    final controller = TextEditingController(text: current == kUncategorized ? '' : current);
    final existing =
        groupByCategory(_products).keys.where((k) => k != kUncategorized).toList();
    // The shop's own categories first, then suggestions for its business type.
    final options = [
      ...existing,
      ...ShopSettings.starterCategories()
          .where((c) => !existing.any((e) => e.toLowerCase() == c.toLowerCase())),
    ];
    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Category for ${product.title}'),
        content: CategoryField(controller: controller, options: options),
        actions: [
          TextButton(
            child: Text(tr('Cancel')),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          TextButton(
            child: Text(tr('Save')),
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) {
                _msg('Please enter a category');
                return;
              }
              Navigator.pop(dialogContext);
              _setCategory(product, value);
            },
          ),
        ],
      ),
    );
  }

  void _showProductDetails(Product product) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(product.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Category: ${categoryOf(product)}'),
            Text('Barcode: ${product.barcode.isEmpty ? '-' : product.barcode}'),
            Text('Buying price: ${tzs(product.buyingPrice)}'),
            Text('Selling price: ${tzs(product.price)}'),
            Text('Profit per item: ${tzs(product.price - product.buyingPrice)}'),
            Text('Stock: ${product.stockQuantity}'),
            Text('Expiry: ${product.expiryDate == null ? 'not set' : DateFormat('d MMM yyyy').format(product.expiryDate!)}'),
            if (product.description != null && product.description!.isNotEmpty)
              Text('Notes: ${product.description}'),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Add stock'),
            onPressed: () {
              Navigator.pop(dialogContext);
              _openRestock(product);
            },
          ),
          TextButton(
            child: Text(product.expiryDate == null ? 'Set expiry' : 'Change expiry'),
            onPressed: () {
              Navigator.pop(dialogContext);
              _editExpiry(product);
            },
          ),
          if (product.expiryDate != null)
            TextButton(
              child: const Text('Remove expiry'),
              onPressed: () {
                Navigator.pop(dialogContext);
                _clearExpiry(product);
              },
            ),
          TextButton(
            child: const Text('Change category'),
            onPressed: () {
              Navigator.pop(dialogContext);
              _showChangeCategoryDialog(product);
            },
          ),
          TextButton(
            child: const Text('Close'),
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
  }
}
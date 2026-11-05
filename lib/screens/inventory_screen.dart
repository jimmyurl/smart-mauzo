import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/supabase_service.dart';
import '../utils/money.dart';
import 'add_product_screen.dart';

/// Products: list, search, update stock, and register new items.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  static const int _lowStock = 5;

  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _search = TextEditingController();
  List<Product> _products = [];
  String _query = '';
  bool _isLoading = true;
  String? _error;

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
      final products = await _supabaseService.getProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '$e';
      });
    }
  }

  List<Product> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products
        .where((p) => p.title.toLowerCase().contains(q) || p.barcode.contains(q))
        .toList();
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

  Future<void> _openAddProduct() async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadInventory),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search by name or barcode',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
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
              ElevatedButton(onPressed: _loadInventory, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final items = _visible;
    if (items.isEmpty) {
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
        itemCount: items.length,
        itemBuilder: (context, index) {
          final product = items[index];
          final color = _stockColor(product.stockQuantity);
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ListTile(
              onTap: () => _showProductDetails(product),
              leading: CircleAvatar(
                backgroundColor: color.withOpacity(0.12),
                child: Icon(Icons.inventory_2_outlined, color: color),
              ),
              title: Text(product.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${tzs(product.price)}  •  ${product.stockQuantity} in stock'
                '${product.stockQuantity <= 0 ? '  (out of stock)' : product.stockQuantity <= _lowStock ? '  (low)' : ''}',
                style: TextStyle(color: color),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Update stock',
                onPressed: () => _showUpdateStockDialog(product),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showUpdateStockDialog(Product product) {
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
            child: const Text('Cancel'),
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

  void _showProductDetails(Product product) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(product.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Barcode: ${product.barcode.isEmpty ? '-' : product.barcode}'),
            Text('Price: ${tzs(product.price)}'),
            Text('Stock: ${product.stockQuantity}'),
            if (product.description != null && product.description!.isNotEmpty)
              Text('Notes: ${product.description}'),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Close'),
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
  }
}
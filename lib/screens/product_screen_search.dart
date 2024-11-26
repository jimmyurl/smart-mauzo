import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import '../models/product.dart';
import '../services/supabase_service.dart';

// Product Search Screen
class ProductSearchScreen extends StatefulWidget {
  const ProductSearchScreen({Key? key}) : super(key: key);

  @override
  _ProductSearchScreenState createState() => _ProductSearchScreenState();
}

class _ProductSearchScreenState extends State<ProductSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  final SupabaseService _supabaseService = SupabaseService();

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _supabaseService.getProducts();
      setState(() {
        _products = products;
        _filteredProducts = products;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading products: $e')),
      );
    }
  }

  void _filterProducts(String query) {
    setState(() {
      _filteredProducts = _products
          .where((product) =>
              product.title.toLowerCase().contains(query.toLowerCase()) ||
              product.barcode.contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Products'),
        backgroundColor: Colors.blue[900],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or barcode',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: _filterProducts,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredProducts.length,
              itemBuilder: (context, index) {
                final product = _filteredProducts[index];
                return ListTile(
                  leading: Icon(Icons.shopping_bag, color: Colors.blue[900]),
                  title: Text(product.title),
                  subtitle: Text('Stock: ${product.stockQuantity}'),
                  trailing: Text('\$${product.price.toStringAsFixed(2)}'),
                  onTap: () => _showSaleDialog(product),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSaleDialog(Product product) async {
    int quantity = 1;
    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Sell ${product.title}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Price: \$${product.price.toStringAsFixed(2)}'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () {
                      if (quantity > 1) {
                        setState(() => quantity--);
                      }
                    },
                  ),
                  Text('$quantity'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      if (quantity < product.stockQuantity) {
                        setState(() => quantity++);
                      }
                    },
                  ),
                ],
              ),
              Text('Total: \$${(product.price * quantity).toStringAsFixed(2)}'),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('Confirm Sale'),
              onPressed: () async {
                final success =
                    await _supabaseService.recordSale(product, quantity);
                Navigator.pop(context);
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sale recorded successfully')),
                  );
                  _loadProducts(); // Refresh product list
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Error recording sale')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

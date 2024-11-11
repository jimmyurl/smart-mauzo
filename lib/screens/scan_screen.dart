import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/supabase_service.dart';
import '../models/product.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({Key? key}) : super(key: key);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  Product? _currentProduct;
  List<Product> _searchResults = [];
  bool _isOnline = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _setupConnectivityListener();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOnline = connectivityResult != ConnectivityResult.none;
      });
    }
  }

  void _setupConnectivityListener() {
    Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      if (mounted && results.isNotEmpty) {
        setState(() {
          _isOnline = results.first != ConnectivityResult.none;
        });
      }
    });
  }

  Future<void> _onSearchChanged() async {
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    await _searchProducts(query);
  }

  Future<void> _searchProducts(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final products = await _supabaseService.searchProducts(query);
      setState(() {
        _searchResults = products;
      });
    } catch (e) {
      _showError('Error searching products: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _scanBarcode() async {
    try {
      String barcode = await FlutterBarcodeScanner.scanBarcode(
        '#ff6666',
        'Cancel',
        true,
        ScanMode.BARCODE,
      );

      if (barcode != '-1') {
        setState(() {
          _isLoading = true;
        });

        try {
          final product = await _supabaseService.getProductByBarcode(barcode);
          setState(() {
            _currentProduct = product;
          });

          if (product == null) {
            _showError('Product not found');
          }
        } catch (e) {
          _showError('Error fetching product: $e');
        } finally {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      _showError('Error scanning barcode: $e');
    }
  }

  Future<void> _processTransaction() async {
    if (_currentProduct == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Update product quantity
      final updatedProduct = _currentProduct!;
      updatedProduct.stockQuantity--;

      // Record the sale
      await _supabaseService.recordSale(
        updatedProduct.id,
        1,
        updatedProduct.price,
      );

      // Update the product stock
      await _supabaseService.updateProduct(updatedProduct);

      _showSuccess('Sale processed successfully');

      setState(() {
        _currentProduct = updatedProduct;
      });
    } catch (e) {
      _showError('Error processing sale: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final product = _searchResults[index];
          return ListTile(
            title: Text(product.name),
            subtitle: Text('\$${product.price.toStringAsFixed(2)}'),
            trailing: Text('Stock: ${product.stockQuantity}'),
            onTap: () {
              setState(() {
                _currentProduct = product;
                _searchResults = [];
                _searchController.clear();
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildProductCard() {
    if (_currentProduct == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentProduct!.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('Price: \$${_currentProduct!.price.toStringAsFixed(2)}'),
            Text('In Stock: ${_currentProduct!.stockQuantity}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _currentProduct!.stockQuantity > 0
                  ? _processTransaction
                  : null,
              child: const Text('Sell Item'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan & Sell'),
        actions: [
          Icon(
            _isOnline ? Icons.cloud_done : Icons.cloud_off,
            color: _isOnline ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search by product name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt),
                      onPressed: _scanBarcode,
                    ),
                  ],
                ),
              ),
              _buildSearchResults(),
              _buildProductCard(),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}

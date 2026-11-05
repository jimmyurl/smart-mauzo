import 'package:flutter/material.dart';
import 'barcode_scan_page.dart';
import '../models/product.dart';
import '../services/supabase_service.dart';
import 'pesapal_checkout_screen.dart';

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _quantityController = TextEditingController(text: '1');
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  Product? _selectedProduct;
  bool _isLoading = false;
  double _totalAmount = 0.0;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  void _showMessage(String text, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: success ? Colors.green : null),
    );
  }

  Future<void> _fetchProducts() async {
    try {
      setState(() => _isLoading = true);
      final products = await _supabaseService.getProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _filteredProducts = [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('Error fetching products: $e');
    }
  }

  void _filterProducts(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filteredProducts = q.isEmpty
          ? []
          : _products
              .where((p) => p.title.toLowerCase().contains(q) || p.barcode.contains(q))
              .toList();
    });
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProduct = product;
      _searchController.text = product.title;
      _filteredProducts = [];
    });
    _calculateTotal();
  }

  void _clearSelection() {
    setState(() {
      _selectedProduct = null;
      _totalAmount = 0.0;
      _searchController.clear();
    });
  }

  void _calculateTotal() {
    setState(() {
      _totalAmount = _selectedProduct == null ? 0.0 : _selectedProduct!.price * _quantity;
    });
  }

  void _updateQuantity(String value) {
    // An empty field counts as 1 internally but is not overwritten while the user types.
    final parsed = int.tryParse(value) ?? 1;
    _quantity = parsed < 1 ? 1 : parsed;
    _calculateTotal();
  }

  Future<void> _scanProduct() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
    );
    if (code == null || code.isEmpty) return;
    final matches = _products.where((p) => p.barcode == code);
    if (matches.isEmpty) {
      _showMessage('No product found for barcode $code');
      return;
    }
    _selectProduct(matches.first);
  }

  /// Checks product, quantity and stock before any sale or payment starts.
  bool _validate() {
    final product = _selectedProduct;
    if (product == null) {
      _showMessage('Please select a product first');
      return false;
    }
    if (_quantity > product.stockQuantity) {
      _showMessage('Only ${product.stockQuantity} in stock');
      return false;
    }
    return true;
  }

  Future<void> _afterSale(String message) async {
    _showMessage(message, success: true);
    _resetForm();
    await _fetchProducts(); // stock changed, reload
  }

  /// Cash: record the sale directly (existing behaviour).
  Future<void> _cashSale() async {
    if (!_validate()) return;
    setState(() => _isLoading = true);
    final ok = await _supabaseService.recordSale(_selectedProduct!, _quantity);
    if (!mounted) return;
    if (ok) {
      await _afterSale('Cash sale recorded');
    } else {
      setState(() => _isLoading = false);
      _showMessage('Could not record the sale. Please try again.');
    }
  }

  /// M-Pesa / Tigo Pesa / Airtel Money / card via Pesapal.
  /// The server records the sale only after Pesapal confirms payment, so do NOT call recordSale here.
  Future<void> _mobileSale() async {
    if (!_validate()) return;
    final product = _selectedProduct!;
    final phone = _phoneController.text.trim();
    final paid = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PesapalCheckoutScreen(
          productId: product.id,
          quantity: _quantity,
          total: _totalAmount,
          customerPhone: phone.isEmpty ? null : phone,
        ),
      ),
    );
    if (!mounted) return;
    if (paid == true) {
      await _afterSale('Payment received, sale recorded');
    } else {
      _showMessage('Payment was not completed');
    }
  }

  void _resetForm() {
    setState(() {
      _selectedProduct = null;
      _quantity = 1;
      _totalAmount = 0.0;
      _quantityController.text = '1';
      _searchController.clear();
      _phoneController.clear();
      _filteredProducts = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Sale'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Product',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // Option 1: scan
                  Card(
                    elevation: 2,
                    child: ListTile(
                      leading: Icon(Icons.qr_code_scanner, color: Colors.blue[900]),
                      title: const Text('Scan Product'),
                      subtitle: const Text('Scan barcode to select product'),
                      trailing: ElevatedButton(
                        onPressed: _scanProduct,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[900],
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Scan'),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Row(children: [
                    Expanded(child: Divider()),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('OR')),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 16),

                  // Option 2: search
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.search, color: Colors.blue[900]),
                            const SizedBox(width: 8),
                            const Text('Search Product',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                          ]),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              hintText: 'Type product name or barcode...',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: _filterProducts,
                          ),
                          if (_filteredProducts.isNotEmpty && _selectedProduct == null)
                            Container(
                              height: 200,
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                itemCount: _filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final product = _filteredProducts[index];
                                  return ListTile(
                                    title: Text(product.title),
                                    subtitle: Text(
                                        'TZS ${product.price.toStringAsFixed(0)}  •  ${product.stockQuantity} in stock'),
                                    trailing: Text(product.barcode),
                                    onTap: () => _selectProduct(product),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  if (_selectedProduct != null) ...[
                    const Text('Selected Product',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_selectedProduct!.title,
                                          style: const TextStyle(
                                              fontSize: 18, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Price: TZS ${_selectedProduct!.price.toStringAsFixed(0)}  •  ${_selectedProduct!.stockQuantity} in stock',
                                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: _clearSelection,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(children: [
                              const Text('Quantity:',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextField(
                                  controller: _quantityController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding:
                                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  onChanged: _updateQuantity,
                                ),
                              ),
                            ]),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total Amount:',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  Text('TZS ${_totalAmount.toStringAsFixed(0)}',
                                      style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue[900])),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Cash
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _cashSale,
                        icon: const Icon(Icons.payments),
                        label: const Text('Cash Sale',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Mobile money / card
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Customer phone (optional)',
                        hintText: '07XXXXXXXX',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_android),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _mobileSale,
                        icon: const Icon(Icons.smartphone),
                        label: const Text('Pay with M-Pesa / Tigo / Airtel / Card',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[900],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _searchController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; 
import 'package:smart_mauzo/models/product.dart';
import 'package:smart_mauzo/models/sale.dart';
import 'package:smart_mauzo/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SaleScreen extends StatefulWidget {
  const SaleScreen({Key? key}) : super(key: key);

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  // Fixed: Initialize SupabaseService without parameters
  final SupabaseService _supabaseService = SupabaseService();
  Product? _scannedProduct;
  int _quantity = 1;
  final TextEditingController _quantityController = TextEditingController(text: '1');

  Future<void> _scanBarcode() async {
    try {
      // Navigate to the MobileScannerPage and get the scanned barcode
      final barcode = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => MobileScannerPage(),
        ),
      );

      if (barcode != null && barcode.isNotEmpty) {
        final product = await _supabaseService.getProductByBarcode(barcode);
        if (product != null) {
          setState(() {
            _scannedProduct = product;
          });
        } else {
          _showError('Product not found');
        }
      }
    } catch (e) {
      _showError('Error scanning barcode: $e');
    }
  }

  Future<void> _recordSale() async {
    if (_scannedProduct == null) return;

    if (_quantity > _scannedProduct!.stockQuantity) {
      _showError('Insufficient stock');
      return;
    }

    // Fixed: Pass Product and quantity directly instead of creating Sale object
    final success = await _supabaseService.recordSale(_scannedProduct!, _quantity);

    if (success) {
      _showSuccess();
      setState(() {
        _scannedProduct = null;
        _quantity = 1;
        _quantityController.text = '1';
      });
    } else {
      _showError('Failed to record sale');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sale recorded successfully'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Sale'),
        backgroundColor: Colors.blue[900],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _scanBarcode,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan Product'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[900],
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            if (_scannedProduct != null) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _scannedProduct!.title, // Fixed: Changed from name to title
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Price: \$${_scannedProduct!.price.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      Text(
                        'Available Stock: ${_scannedProduct!.stockQuantity}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _quantityController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Quantity',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _quantity = int.tryParse(value) ?? 1;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'Total: \$${(_scannedProduct!.price * _quantity).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _recordSale,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Complete Sale'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Add the MobileScannerPage class for barcode scanning
class MobileScannerPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Barcode')),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final String code = barcodes.first.rawValue ?? '';
            Navigator.of(context).pop(code);
          }
        },
      ),
    );
  }
}
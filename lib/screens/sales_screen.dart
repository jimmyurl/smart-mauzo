import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../models/sale.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({Key? key}) : super(key: key);

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  List<Sale> _sales = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchSales();
  }

  Future<void> _fetchSales() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final sales = await _supabaseService.fetchSales();

      if (mounted) {
        setState(() {
          _sales = sales;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error fetching sales: $e';
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSales,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchSales,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _sales.isEmpty
                  ? const Center(
                      child: Text('No sales found'),
                    )
                  : ListView.builder(
                      itemCount: _sales.length,
                      itemBuilder: (context, index) {
                        final sale = _sales[index];
                        return ListTile(
                          title: Text(sale.productTitle),
                          subtitle: Text(
                            'Quantity: ${sale.quantity}, Total: \$${sale.total.toStringAsFixed(2)}',
                          ),
                          trailing: Text(
                            sale.timestamp
                                .toString()
                                .substring(0, 16), // Truncate timestamp
                          ),
                        );
                      },
                    ),
    );
  }
}

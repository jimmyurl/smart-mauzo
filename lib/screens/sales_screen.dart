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

  @override
  void initState() {
    super.initState();
    _fetchSales();
  }

  Future<void> _fetchSales() async {
    try {
      final sales = await _supabaseService.fetchSales();
      if (mounted) {
        setState(() {
          _sales = sales;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching sales: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
      ),
      body: _sales.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _sales.length,
              itemBuilder: (context, index) {
                final sale = _sales[index];
                return ListTile(
                  title: Text(sale.productTitle),
                  subtitle: Text(
                      'Quantity: ${sale.quantity}, Total: \$${sale.total.toStringAsFixed(2)}'),
                  trailing: Text(sale.timestamp.toString()),
                );
              },
            ),
    );
  }
}

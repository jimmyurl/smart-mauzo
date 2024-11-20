import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../models/sale.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({Key? key}) : super(key: key);

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  List<Sale> _sales = [];
  double _totalRevenue = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchSalesData();
  }

  Future<void> _fetchSalesData() async {
    try {
      final sales = await _supabaseService.fetchSales();
      double totalRevenue = 0.0;
      for (final sale in sales) {
        totalRevenue += sale.total;
      }
      if (mounted) {
        setState(() {
          _sales = sales;
          _totalRevenue = totalRevenue;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching sales data: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report'),
      ),
      body: _sales.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Total Revenue: \$${_totalRevenue.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
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
                ),
              ],
            ),
    );
  }
}

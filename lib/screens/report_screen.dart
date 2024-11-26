import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../models/sale.dart';

// Reports Screen
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  _ReportsScreenState createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  List<Sale> _sales = [];
  bool _isLoading = true;
  String _selectedPeriod = 'Today';
  final List<String> _periods = ['Today', 'Week', 'Month', 'Year'];

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    try {
      setState(() => _isLoading = true);
      final sales = await _supabaseService.fetchSales();
      setState(() {
        _sales = _filterSalesByPeriod(sales, _selectedPeriod);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading sales: $e')),
      );
    }
  }

  List<Sale> _filterSalesByPeriod(List<Sale> sales, String period) {
    final now = DateTime.now();
    final startDate = switch (period) {
      'Today' => DateTime(now.year, now.month, now.day),
      'Week' => now.subtract(const Duration(days: 7)),
      'Month' => DateTime(now.year, now.month - 1, now.day),
      'Year' => DateTime(now.year - 1, now.month, now.day),
      _ => now,
    };

    return sales.where((sale) => sale.timestamp.isAfter(startDate)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sales Reports'),
          backgroundColor: Colors.blue[900],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Transactions'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildOverviewTab(),
            _buildTransactionsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final totalSales = _sales.fold(0.0, (sum, sale) => sum + sale.total);
    final totalItems = _sales.fold(0, (sum, sale) => sum + sale.quantity);
    final averageOrder = _sales.isEmpty ? 0.0 : totalSales / _sales.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPeriodSelector(),
          const SizedBox(height: 16),
          _buildMetricCard('Total Sales', '\$${totalSales.toStringAsFixed(2)}'),
          _buildMetricCard('Total Items Sold', totalItems.toString()),
          _buildMetricCard(
            'Average Order Value',
            '\$${averageOrder.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 16),
          _buildSalesChart(),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return DropdownButton<String>(
      value: _selectedPeriod,
      items: _periods.map((String period) {
        return DropdownMenuItem<String>(
          value: period,
          child: Text(period),
        );
      }).toList(),
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() {
            _selectedPeriod = newValue;
            _loadSales();
          });
        }
      },
    );
  }

  Widget _buildMetricCard(String title, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesChart() {
    // Implementation for sales chart
    // You can use charts_flutter package for this
    return Container(); // Placeholder
  }

  Widget _buildTransactionsTab() {
    return ListView.builder(
      itemCount: _sales.length,
      itemBuilder: (context, index) {
        final sale = _sales[index];
        return ListTile(
          title: Text(sale.productTitle),
          subtitle: Text(
            DateFormat('MMM dd, yyyy HH:mm').format(sale.timestamp),
          ),
          trailing: Text(
            '\$${sale.total.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          onTap: () => _showTransactionDetails(sale),
        );
      },
    );
  }

  void _showTransactionDetails(Sale sale) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Transaction ${sale.id}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Product: ${sale.productTitle}'),
            Text('Quantity: ${sale.quantity}'),
            Text('Total: \$${sale.total.toStringAsFixed(2)}'),
            Text(
                'Date: ${DateFormat('MMM dd, yyyy HH:mm').format(sale.timestamp)}'),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Close'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

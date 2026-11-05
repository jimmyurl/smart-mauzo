import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../services/supabase_service.dart';
import '../utils/money.dart';
import 'new_sale_screen.dart';

/// Sales history. The "New sale" button opens the sell form (NewSaleScreen).
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

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
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final sales = await _supabaseService.fetchSales();
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _newSale() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NewSaleScreen()),
    );
    if (mounted) _fetchSales();
  }

  bool _isToday(DateTime t) {
    final l = t.toLocal();
    final n = DateTime.now();
    return l.year == n.year && l.month == n.month && l.day == n.day;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchSales),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newSale,
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('New sale'),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchSales, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_sales.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No sales yet.\nTap "New sale" to make your first one.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
        ),
      );
    }

    final today = _sales.where((s) => _isToday(s.timestamp)).toList();
    final todayTotal = today.fold<double>(0, (sum, s) => sum + s.total);

    return RefreshIndicator(
      onRefresh: _fetchSales,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _sales.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _summaryCard(todayTotal, today.length);
          final sale = _sales[index - 1];
          final color = sale.isMobile ? Colors.blue[800]! : Colors.green[700]!;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withOpacity(0.12),
              child: Icon(sale.isMobile ? Icons.smartphone : Icons.payments, color: color),
            ),
            title: Text(sale.productTitle),
            subtitle: Text(
              '${sale.quantity} item${sale.quantity == 1 ? '' : 's'}  •  '
              '${DateFormat('d MMM, HH:mm').format(sale.timestamp.toLocal())}  •  '
              '${sale.isMobile ? 'Mobile/Card' : 'Cash'}',
            ),
            trailing: Text(tzs(sale.total), style: const TextStyle(fontWeight: FontWeight.bold)),
          );
        },
      ),
    );
  }

  Widget _summaryCard(double total, int count) {
    return Card(
      margin: const EdgeInsets.all(16),
      color: Colors.blue[900],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Today', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text(tzs(total),
                style: const TextStyle(
                    color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('$count sale${count == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/sale.dart';

class SupabaseService {
  static const String SUPABASE_URL = 'YOUR_SUPABASE_URL';
  static const String SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';

  late final SupabaseClient client;
  final _uuid = Uuid();

  Future<void> initialize() async {
    await Supabase.initialize(
      url: SUPABASE_URL,
      anonKey: SUPABASE_ANON_KEY,
    );
    client = Supabase.instance.client;
  }

  // Singleton pattern
  static final SupabaseService _instance = SupabaseService._internal();

  factory SupabaseService() {
    return _instance;
  }

  SupabaseService._internal();

  // Helper method to get client
  SupabaseClient get supabaseClient {
    return client;
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    try {
      final response = await client
          .from('products')
          .select()
          .eq('barcode', barcode)
          .single();

      return Product.fromJson(response);
    } catch (e) {
      print('Error fetching product: $e');
      return null;
    }
  }

  Future<bool> recordSale(Product product, int quantity) async {
    try {
      final String saleId = _uuid.v4();
      final double total = product.price * quantity;

      final sale = Sale(
        id: saleId,
        productId: product.id,
        productTitle: product.title, // Changed from name to title
        quantity: quantity,
        total: total,
        timestamp: DateTime.now(),
      );

      // Record the sale
      await client.from('sales').insert(sale.toJson());

      // Update product stock
      final newStockQuantity = product.stockQuantity - quantity;
      await client
          .from('products')
          .update({'stock_quantity': newStockQuantity}).eq('id', product.id);

      return true;
    } catch (e) {
      print('Error recording sale: $e');
      return false;
    }
  }

  Future<List<Sale>> getRecentSales([int limit = 10]) async {
    try {
      final response = await client
          .from('sales')
          .select()
          .order('timestamp', ascending: false)
          .limit(limit);

      return response.map<Sale>((json) => Sale.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching recent sales: $e');
      return [];
    }
  }
}

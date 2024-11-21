import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../models/sale.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;

  late final SupabaseClient client;
  bool _initialized = false;

  SupabaseService._internal();

  Future<void> initialize() async {
    if (!_initialized) {
      await Supabase.initialize(
        url: 'https://ajlzuhtyyaxlobcljusi.supabase.co',
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFqbHp1aHR5eWF4bG9iY2xqdXNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MjM3MTA1NTAsImV4cCI6MjAzOTI4NjU1MH0.3deZCnbg63e5JUgupnACPfpATw7ViKe9V08Eq9L5G74',
      );
      client = Supabase.instance.client;
      _initialized = true;
    }
  }

  // Returns true if the client is ready to use
  bool get isInitialized => _initialized;

  Future<List<Product>> getProducts() async {
    try {
      final response = await client
          .from('products')
          .select()
          .order('title')
          .then((value) => value as List);

      return response.map((json) => Product.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching products: $e');
      rethrow;
    }
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    try {
      final response = await client
          .from('products')
          .select()
          .eq('barcode', barcode)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        return Product.fromJson(response);
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching product: $e');
      rethrow;
    }
  }

  Future<void> updateProduct(Product product) async {
    try {
      await client
          .from('products')
          .update({
            'stock_quantity': product.stockQuantity,
            'price': product.price,
            'title': product.title,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', product.id)
          .then((value) => null);
    } catch (e) {
      debugPrint('Error updating product: $e');
      rethrow;
    }
  }

  Future<List<Product>> searchProducts(String query) async {
    try {
      final response = await client
          .from('products')
          .select()
          .or('title.ilike.%$query%,barcode.ilike.%$query%')
          .order('title')
          .limit(20)
          .then((value) => value as List);

      return response.map((json) => Product.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error searching products: $e');
      rethrow;
    }
  }

  Future<void> recordSale(
      String productId, int quantity, double totalPrice) async {
    try {
      await client.from('sales').insert({
        'product_id': productId,
        'quantity': quantity,
        'total_price': totalPrice,
        'sale_date': DateTime.now().toIso8601String(),
      }).then((value) => null);
    } catch (e) {
      debugPrint('Error recording sale: $e');
      rethrow;
    }
  }
}

Future<List<Sale>> fetchSales() async {
  try {
    final response = await client
        .from('sales')
        .select('*, products(title)')
        .order('sale_date', ascending: false)
        .limit(100)
        .then((value) => value as List);

    return response.map((json) {
      // Merge product title from the joined products table
      final productTitle = json['products'] != null
          ? json['products']['title'] ?? 'Unknown Product'
          : 'Unknown Product';

      return Sale.fromJson({
        ...json,
        'product_title': productTitle,
      });
    }).toList();
  } catch (e) {
    debugPrint('Error fetching sales: $e');
    rethrow;
  }
}

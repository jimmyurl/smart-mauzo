import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:smart_mauzo/models/product.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:smart_mauzo/screens/scan_screen.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;

  late final SupabaseClient client;

  SupabaseService._internal();

  Future<void> initialize() async {
    await Supabase.initialize(
      url: 'YOUR_SUPABASE_URL',
      anonKey: 'YOUR_SUPABASE_ANON_KEY',
    );
    client = Supabase.instance.client;
  }

  Future<List<Product>> getProducts() async {
    try {
      final response = await client.from('products').select().order('name');

      if (response is List) {
        return response.map((json) => Product.fromJson(json)).toList();
      }
      return [];
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
      await client.from('products').update({
        'stock_quantity': product.stockQuantity,
        'price': product.price,
        'name': product.name,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', product.id);
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
          .or('name.ilike.%$query%,barcode.ilike.%$query%')
          .order('name')
          .limit(20);

      if (response is List) {
        return response.map((json) => Product.fromJson(json)).toList();
      }
      return [];
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
      });
    } catch (e) {
      debugPrint('Error recording sale: $e');
      rethrow;
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../models/sale.dart';

class SupabaseService {
  // ===================================================================
  //  PASTE YOUR PROJECT VALUES HERE (Supabase dashboard -> Project
  //  Settings -> API: "Project URL" and the "anon public" key).
  //  The anon key is safe to ship in the app; data is protected by the
  //  row-level-security rules in smart_mauzo_schema.sql.
  // ===================================================================
  static const String SUPABASE_URL = 'YOUR_SUPABASE_URL';
  static const String SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';

  // Smart Mauzo tables live under the sm_ prefix (shared Supabase project).
  static const String _products = 'sm_products';
  static const String _sales = 'sm_sales';

  /// False until the two values above have been replaced.
  static bool get isConfigured =>
      SUPABASE_URL.startsWith('https://') &&
      !SUPABASE_ANON_KEY.startsWith('YOUR_') &&
      SUPABASE_ANON_KEY.length > 20;

  Future<void> initialize() async {
    await Supabase.initialize(url: SUPABASE_URL, anonKey: SUPABASE_ANON_KEY);
  }

  // Singleton pattern
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;
  SupabaseClient get supabaseClient => client;

  // ---------------------------------------------------------------- products
  Future<Product?> getProductByBarcode(String barcode) async {
    try {
      final response =
          await client.from(_products).select().eq('barcode', barcode).maybeSingle();
      return response == null ? null : Product.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching product: $e');
      return null;
    }
  }

  Future<List<Product>> getProducts() async {
    try {
      final response = await client.from(_products).select().order('title');
      return response.map<Product>((json) => Product.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching products: $e');
      throw 'Failed to fetch products: $e';
    }
  }

  /// Registers a new item. The shop is filled in by the database from the
  /// signed-in user; only the shop owner is allowed to do this.
  /// Throws a [PostgrestException] (e.g. code 23505 = barcode already used).
  Future<void> addProduct({
    required String title,
    required double price,
    required int stock,
    String barcode = '',
    String? description,
  }) async {
    await client.from(_products).insert({
      'title': title,
      'price': price,
      'stock_quantity': stock,
      'barcode': barcode,
      'description': description,
    });
  }

  Future<bool> updateProductStock(String productId, int newStockQuantity) async {
    try {
      await client
          .from(_products)
          .update({'stock_quantity': newStockQuantity}).eq('id', productId);
      return true;
    } catch (e) {
      debugPrint('Error updating product stock: $e');
      return false;
    }
  }

  // ------------------------------------------------------------------- sales
  /// Cash sale. Done in one database step that checks and reduces stock.
  Future<bool> recordSale(Product product, int quantity) async {
    try {
      await client.rpc('sm_record_sale',
          params: {'p_product_id': product.id, 'p_quantity': quantity});
      return true;
    } catch (e) {
      debugPrint('Error recording sale: $e');
      return false;
    }
  }

  Future<List<Sale>> getRecentSales([int limit = 10]) async {
    try {
      final response = await client
          .from(_sales)
          .select()
          .order('timestamp', ascending: false)
          .limit(limit);
      return response.map<Sale>((json) => Sale.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching recent sales: $e');
      return [];
    }
  }

  Future<List<Sale>> fetchSales() async {
    try {
      final response =
          await client.from(_sales).select().order('timestamp', ascending: false);
      return response.map<Sale>((json) => Sale.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching all sales: $e');
      throw 'Failed to fetch sales: $e';
    }
  }
}
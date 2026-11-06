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
  static const String SUPABASE_URL = 'https://eiaxcjpgmrqsmmdevavs.supabase.co';
  static const String SUPABASE_ANON_KEY = 'sb_publishable_jrCLORcW9NI-jg0WJXO5UQ_zZp9Jy6B';

  // Smart Mauzo tables live under the sm_ prefix (shared Supabase project).
  static const String _products = 'sm_products';
  static const String _sales = 'sm_sales';
  static const String _suppliers = 'sm_suppliers';
  static const String _purchases = 'sm_stock_purchases';

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
    double buyingPrice = 0,
    required int stock,
    String barcode = '',
    String? description,
    String category = 'Uncategorized',
  }) async {
    await client.from(_products).insert({
      'title': title,
      'price': price,
      'buying_price': buyingPrice,
      'stock_quantity': stock,
      'barcode': barcode,
      'description': description,
      'category': category.trim().isEmpty ? 'Uncategorized' : category.trim(),
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

  Future<bool> updateProductCategory(String productId, String category) async {
    try {
      await client
          .from(_products)
          .update({'category': category.trim()}).eq('id', productId);
      return true;
    } catch (e) {
      debugPrint('Error updating product category: $e');
      return false;
    }
  }

  // --------------------------------------------------------- suppliers / stock
  /// Names of existing suppliers (autocomplete in the restock screen).
  Future<List<String>> getSupplierNames() async {
    try {
      final rows = await client.from(_suppliers).select('name').order('name');
      return (rows as List).map<String>((r) => r['name'] as String).toList();
    } catch (e) {
      debugPrint('Error fetching suppliers: $e');
      return [];
    }
  }

  /// Adds stock bought from a supplier, saves the new buying price and logs the
  /// purchase in ONE database step (sm_restock_product). Returns null on success,
  /// otherwise an error message to show.
  Future<String?> restockProduct({
    required String productId,
    required int quantity,
    required double buyingPrice,
    String supplierName = '',
    String supplierPhone = '',
    String note = '',
  }) async {
    try {
      await client.rpc('sm_restock_product', params: {
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_buying_price': buyingPrice,
        'p_supplier_name': supplierName.isEmpty ? null : supplierName,
        'p_supplier_phone': supplierPhone.isEmpty ? null : supplierPhone,
        'p_note': note.isEmpty ? null : note,
      });
      return null;
    } on PostgrestException catch (e) {
      debugPrint('Error restocking: ${e.message}');
      return e.message;
    } catch (e) {
      debugPrint('Error restocking: $e');
      return '$e';
    }
  }

  /// Purchase history (newest first), optionally for a single product.
  /// Each row includes the supplier name under 'sm_suppliers'.
  Future<List<Map<String, dynamic>>> getStockPurchases({String? productId}) async {
    try {
      var query = client.from(_purchases).select('*, sm_suppliers(name)');
      if (productId != null) query = query.eq('product_id', productId);
      final rows = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('Error fetching stock purchases: $e');
      return [];
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

  /// Cash sale of a whole cart in ONE database transaction: either every line is
  /// recorded and stock reduced, or nothing is. Returns null on success, otherwise
  /// an error message to show. Each item: {'product_id': id, 'quantity': n}.
  Future<String?> recordCartSale(List<Map<String, dynamic>> items) async {
    try {
      await client.rpc('sm_record_sale_cart', params: {'p_items': items});
      return null;
    } on PostgrestException catch (e) {
      debugPrint('Error recording cart sale: ${e.message}');
      return e.message;
    } catch (e) {
      debugPrint('Error recording cart sale: $e');
      return '$e';
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
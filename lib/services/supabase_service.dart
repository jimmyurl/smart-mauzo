import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../models/sale.dart';
import 'offline_store.dart';

/// What happened when a cart sale was sent to the server.
enum SaleOutcome {
  saved, // recorded (or the server already had this receipt)
  network, // no connection, timeout or session problem: safe to try again later
  rejected, // the server answered and refused it ([SaleResult.message] says why)
}

class SaleResult {
  final SaleOutcome outcome;
  final String? message;

  /// The order number the server gave a saved sale (null if it could not be read).
  final int? orderNo;
  const SaleResult(this.outcome, [this.message, this.orderNo]);
}

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

  /// A phone that started without internet can know who the user is (remembered
  /// sign-in) without having a live session yet. The server would then treat the
  /// request as anonymous and answer with an EMPTY list instead of an error, so
  /// fail here and let the screens use their saved copy.
  void _requireLiveSession() {
    if (client.auth.currentSession == null && OfflineIdentity.isRemembered) {
      throw 'Waiting to sign in again (no connection)';
    }
  }

  /// Text safe to show to a shop owner. Technical details (socket errors, URLs,
  /// error numbers) only go to the debug log, never to the screen.
  static String friendlyError(Object e) {
    final text = '$e'.toLowerCase();
    const networkHints = [
      'socketexception', 'clientexception', 'timeoutexception', 'handshake',
      'connection', 'network', 'failed host lookup', 'waiting to sign in',
      'jwt', 'not signed in',
    ];
    if (networkHints.any(text.contains)) {
      return 'No internet connection.\nYour data will load again when you are back online.';
    }
    return 'Something went wrong. Please try again.';
  }

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
      _requireLiveSession();
      final response = await client.from(_products).select().order('title');
      final products =
          response.map<Product>((json) => Product.fromJson(json)).toList();
      // Keep an offline copy fresh every time products load (not awaited).
      OfflineStore().saveProducts(products);
      return products;
    } catch (e) {
      debugPrint('Error fetching products: $e');
      throw friendlyError(e);
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

  /// Sets (or clears, with null) the expiry date of a product. Owner only.
  Future<bool> updateProductExpiry(String productId, DateTime? date) async {
    try {
      final value = date == null
          ? null
          : '${date.year.toString().padLeft(4, '0')}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}';
      await client.from(_products).update({'expiry_date': value}).eq('id', productId);
      return true;
    } catch (e) {
      debugPrint('Error updating product expiry: $e');
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
      var query = client.from(_purchases).select('*, sm_suppliers(*)');
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

  /// Cash sale of a cart, safe to send more than once. [receiptId] is made on the
  /// phone; the server ignores a receipt it already recorded. [soldAt] is when the
  /// sale really happened. [offline] is true only for a sale that was kept on the
  /// phone and is being sent later: it is recorded even if stock ran out meanwhile.
  Future<SaleResult> submitCartSale({
    required List<Map<String, dynamic>> items,
    required String receiptId,
    required DateTime soldAt,
    bool offline = false,
  }) async {
    try {
      await client.rpc('sm_record_sale_cart', params: {
        'p_items': items,
        'p_receipt_id': receiptId,
        'p_sold_at': soldAt.toUtc().toIso8601String(),
        'p_offline': offline,
      }).timeout(const Duration(seconds: 20));

      // Which number did this order get? (Only for the message; never fails the sale.)
      int? orderNo;
      try {
        final row = await client
            .from(_sales)
            .select('order_no')
            .eq('receipt_id', receiptId)
            .limit(1)
            .maybeSingle()
            .timeout(const Duration(seconds: 8));
        orderNo = (row?['order_no'] as num?)?.toInt();
      } catch (_) {}
      return SaleResult(SaleOutcome.saved, null, orderNo);
    } on PostgrestException catch (e) {
      debugPrint('Error recording cart sale: ${e.message}');
      if (_isTransient(e)) return SaleResult(SaleOutcome.network, e.message);
      return SaleResult(SaleOutcome.rejected, e.message);
    } on AuthException catch (e) {
      // Not signed in right now: keep the sale and try again later.
      return SaleResult(SaleOutcome.network, e.message);
    } catch (e) {
      // SocketException, TimeoutException, ClientException ...: no usable connection.
      debugPrint('Cart sale not sent: $e');
      return SaleResult(SaleOutcome.network, '$e');
    }
  }

  /// Server-side problems that say nothing about the sale itself (gateway errors,
  /// deadlocks, expired sign-in). The sale is kept and sent again later.
  static bool _isTransient(PostgrestException e) {
    final code = e.code ?? '';
    final status = int.tryParse(code);
    if (status != null && status >= 500) return true;
    if (code == 'PGRST301' || code == 'PGRST303') return true; // JWT problems
    if (code == '57014') return true; // statement timeout
    if (code.startsWith('08') || // connection problems
        code.startsWith('40') || // deadlock / serialization failure
        code.startsWith('53') || // out of resources
        code.startsWith('55')) { // lock not available
      return true;
    }
    return e.message.contains('not signed in') || e.message.contains('JWT');
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

  /// The server saves a credit sale like a cash sale. The credit book knows which
  /// orders were on credit, so mark those sales here and every screen shows them
  /// as "Credit". If the credit book cannot be read, sales are shown as before.
  Future<List<Sale>> _markCreditSales(List<Sale> sales) async {
    try {
      final rows = await client
          .from('sm_credit_entries')
          .select('order_no')
          .eq('kind', 'sale')
          .timeout(const Duration(seconds: 10));
      final credit = <int>{
        for (final r in rows as List)
          if ((r as Map)['order_no'] != null) (r['order_no'] as num).toInt()
      };
      if (credit.isEmpty) return sales;
      return [
        for (final s in sales)
          (s.orderNo != null && credit.contains(s.orderNo)) ? s.withPaymentMethod('credit') : s
      ];
    } catch (_) {
      return sales;
    }
  }

  Future<List<Sale>> fetchSales() async {
    try {
      _requireLiveSession();
      // Cashiers get no buying prices (so no profit figures); the database already
      // limits them to the sales they made themselves.
      final columns = OfflineIdentity.isOwner
          ? '*'
          : 'id,product_id,product_title,quantity,total,timestamp,payment_method,sold_by,order_no';
      final response =
          await client.from(_sales).select(columns).order('timestamp', ascending: false);
      final sales = response.map<Sale>((json) => Sale.fromJson(json)).toList();
      return await _markCreditSales(sales);
    } catch (e) {
      debugPrint('Error fetching all sales: $e');
      throw friendlyError(e);
    }
  }
}
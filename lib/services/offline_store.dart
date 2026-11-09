import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import '../models/sale.dart';

/// A cash sale that is waiting to reach the server.
class PendingSale {
  /// Made on the phone. The server uses it to ignore a sale it already has, so
  /// sending the same sale twice can never record it twice.
  final String receiptId;
  final String userId;
  final List<Map<String, dynamic>> items; // {'product_id': id, 'quantity': n}
  final double total; // what the cashier saw (only shown in the banner)
  final DateTime soldAt;
  final String? error; // set when the server refused the sale

  const PendingSale({
    required this.receiptId,
    required this.userId,
    required this.items,
    required this.total,
    required this.soldAt,
    this.error,
  });

  PendingSale withError(String? message) => PendingSale(
        receiptId: receiptId,
        userId: userId,
        items: items,
        total: total,
        soldAt: soldAt,
        error: message,
      );

  Map<String, dynamic> toJson() => {
        'receipt_id': receiptId,
        'user_id': userId,
        'items': items,
        'total': total,
        'sold_at': soldAt.toIso8601String(),
        'error': error,
      };

  factory PendingSale.fromJson(Map<String, dynamic> j) => PendingSale(
        receiptId: j['receipt_id'] as String,
        userId: j['user_id'] as String,
        items: [
          for (final e in j['items'] as List) Map<String, dynamic>.from(e as Map)
        ],
        total: (j['total'] as num).toDouble(),
        soldAt: DateTime.parse(j['sold_at'] as String),
        error: j['error'] as String?,
      );
}

/// Remembers who is signed in on this phone, and whether they already have a shop,
/// so the app can open without internet. Cleared on sign-out.
class OfflineIdentity {
  static const _key = 'sm_identity_v1';
  static String? _userId;
  static bool _hasShop = false;
  static String? _refreshToken;
  static String? _role; // 'owner' | 'cashier' (last known)

  /// True only when this phone knows the signed-in person owns the shop. Unknown
  /// counts as "not owner", so nothing owner-only is shown by mistake.
  static bool get isOwner => _role == 'owner';

  static String? get userId => _userId;
  static bool get isRemembered => _userId != null;
  static String? get refreshToken => _refreshToken;
  static bool hasShop(String uid) => _userId == uid && _hasShop;

  /// Call once at start-up, before the app is shown.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _userId = m['uid'] as String?;
      _hasShop = m['has_shop'] == true;
      _refreshToken = m['refresh'] as String?;
      _role = m['role'] as String?;
    } catch (e) {
      debugPrint('Could not read the remembered sign-in: $e');
    }
  }

  /// Call for every auth event: remembers a live session, forgets on sign-out.
  static void onAuth(AuthState state) {
    if (state.event == AuthChangeEvent.signedOut) {
      forget();
    } else if (state.session != null) {
      rememberSession(state.session!);
    }
  }

  static void rememberSession(Session s) {
    if (_userId != s.user.id) {
      _hasShop = false;
      _role = null;
    }
    _userId = s.user.id;
    _refreshToken = s.refreshToken;
    _save();
  }

  static Future<void> setHasShop(String uid, bool value) async {
    if (_userId != uid) return;
    _hasShop = value;
    await _save();
  }

  /// Remembers the person's role in the shop (set whenever the shop is loaded).
  static Future<void> setRole(String uid, String? role) async {
    if (_userId != uid || _role == role) return;
    _role = role;
    await _save();
  }

  static void forget() {
    _userId = null;
    _hasShop = false;
    _role = null;
    _refreshToken = null;
    _save();
  }

  static Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_userId == null) {
        await prefs.remove(_key);
        return;
      }
      await prefs.setString(
        _key,
        jsonEncode({
          'uid': _userId,
          'has_shop': _hasShop,
          'refresh': _refreshToken,
          'role': _role,
        }),
      );
    } catch (e) {
      debugPrint('Could not save the remembered sign-in: $e');
    }
  }
}

/// Small wrapper around SharedPreferences: the offline copy of the product list
/// and the queue of sales that have not reached the server yet.
/// The sales list saved on the phone, and when it was saved.
class SavedSales {
  final List<Sale> sales;
  final DateTime? savedAt;
  const SavedSales(this.sales, this.savedAt);
}

class OfflineStore {
  static const _kQueue = 'sm_offline_queue_v1';
  static const _kFailed = 'sm_offline_failed_v1';
  static String _kProducts(String uid) => 'sm_offline_products_v1_$uid';

  String? get _uid =>
      Supabase.instance.client.auth.currentUser?.id ?? OfflineIdentity.userId;

  // ---------------------------------------------------------------- products
  /// Saves the product list as it is right now. The text is built before the first
  /// `await`, so changing stock on the objects afterwards does not affect the copy.
  Future<void> saveProducts(List<Product> products) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final raw = jsonEncode([for (final p in products) p.toJson()]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kProducts(uid), raw);
    } catch (e) {
      debugPrint('Could not save the offline product list: $e');
    }
  }

  /// The last saved product list for the signed-in user, or null if there is none.
  Future<List<Product>?> loadProducts() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kProducts(uid));
      if (raw == null) return null;
      return [
        for (final e in jsonDecode(raw) as List)
          Product.fromJson(Map<String, dynamic>.from(e as Map))
      ];
    } catch (e) {
      debugPrint('Could not read the offline product list: $e');
      return null;
    }
  }

  // ------------------------------------------------------------------- sales
  static String _kSales(String uid) => 'sm_offline_sales_v1_$uid';

  /// Only the newest sales are kept, so the saved copy stays small and quick.
  static const int _maxSavedSales = 3000;

  /// Saves the sales list (newest first) so Home, Sales and Reports open offline.
  Future<void> saveSales(List<Sale> sales) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final newest = sales.length > _maxSavedSales ? sales.sublist(0, _maxSavedSales) : sales;
      final raw = jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'sales': [for (final s in newest) s.toJson()],
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSales(uid), raw);
    } catch (e) {
      debugPrint('Could not save the offline sales list: $e');
    }
  }

  /// The last saved sales list for the signed-in user, or null if there is none.
  Future<SavedSales?> loadSales() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSales(uid));
      if (raw == null) return null;
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return SavedSales(
        [for (final e in m['sales'] as List) Sale.fromJson(Map<String, dynamic>.from(e as Map))],
        m['saved_at'] == null ? null : DateTime.tryParse('${m['saved_at']}'),
      );
    } catch (e) {
      debugPrint('Could not read the offline sales list: $e');
      return null;
    }
  }

  // ------------------------------------------------------------------ queues
  Future<List<PendingSale>> loadQueue() => _loadList(_kQueue);
  Future<void> saveQueue(List<PendingSale> list) => _saveList(_kQueue, list);

  /// Sales the server refused (for example a product that was deleted).
  Future<List<PendingSale>> loadFailed() => _loadList(_kFailed);
  Future<void> saveFailed(List<PendingSale> list) => _saveList(_kFailed, list);

  Future<List<PendingSale>> _loadList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return [];
      return [
        for (final e in jsonDecode(raw) as List)
          PendingSale.fromJson(Map<String, dynamic>.from(e as Map))
      ];
    } catch (e) {
      debugPrint('Could not read $key: $e');
      return [];
    }
  }

  Future<void> _saveList(String key, List<PendingSale> list) async {
    final raw = jsonEncode([for (final s in list) s.toJson()]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, raw);
  }
}
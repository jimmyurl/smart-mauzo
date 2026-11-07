import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';

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

/// Small wrapper around SharedPreferences: the offline copy of the product list
/// and the queue of sales that have not reached the server yet.
class OfflineStore {
  static const _kQueue = 'sm_offline_queue_v1';
  static const _kFailed = 'sm_offline_failed_v1';
  static String _kProducts(String uid) => 'sm_offline_products_v1_$uid';

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

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
import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import 'offline_store.dart';
import 'supabase_service.dart';

/// Keeps cash sales made without internet on the phone and sends them to the
/// server, oldest first, as soon as a connection is back.
///
/// Safe to retry: every sale carries a receipt id made on the phone and the server
/// ignores a receipt it has already recorded, so a sale can never be counted twice,
/// even if the connection drops right after the server saved it.
class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final OfflineStore _store = OfflineStore();
  final SupabaseService _api = SupabaseService();

  List<PendingSale> _queue = [];
  List<PendingSale> _failed = [];
  bool _online = true;
  bool _syncing = false;
  bool _started = false;

  /// Goes up by one each time at least one waiting sale reached the server.
  final ValueNotifier<int> syncedTick = ValueNotifier<int>(0);

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  /// Only the entries of the signed-in user (a shared phone must never send one
  /// person's sales under another account).
  List<PendingSale> _mine(List<PendingSale> list) {
    final uid = _userId;
    return [
      for (final s in list)
        if (s.userId == uid) s
    ];
  }

  bool get online => _online;
  bool get syncing => _syncing;
  int get pendingCount => _mine(_queue).length;
  double get pendingTotal => _mine(_queue).fold<double>(0, (sum, s) => sum + s.total);
  List<PendingSale> get failed => _mine(_failed);

  /// Units already sold on this phone that the server does not know about yet.
  Map<String, int> get pendingQuantities {
    final result = <String, int>{};
    for (final sale in _mine(_queue)) {
      for (final item in sale.items) {
        final id = item['product_id'] as String;
        result[id] = (result[id] ?? 0) + (item['quantity'] as num).toInt();
      }
    }
    return result;
  }

  /// Lowers the stock of [products] by what is waiting in the queue, so the
  /// same item cannot be sold twice on this phone.
  List<Product> applyPending(List<Product> products) {
    final pending = pendingQuantities;
    if (pending.isEmpty) return products;
    for (final p in products) {
      final n = pending[p.id];
      if (n != null) p.stockQuantity = math.max(0, p.stockQuantity - n);
    }
    return products;
  }

  bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  /// Call once at start-up, after Supabase.initialize().
  Future<void> init() async {
    if (_started) return;
    _started = true;

    _queue = await _store.loadQueue();
    _failed = await _store.loadFailed();
    _online = _hasConnection(await Connectivity().checkConnectivity());

    Connectivity().onConnectivityChanged.listen((results) {
      final wasOnline = _online;
      _online = _hasConnection(results);
      notifyListeners();
      if (_online && !wasOnline) sync();
    });

    // A different user signing in changes which queue entries belong to us.
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
      sync();
    });

    WidgetsBinding.instance.addObserver(this);
    Timer.periodic(const Duration(seconds: 60), (_) => sync());

    notifyListeners();
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sync();
  }

  /// Adds a sale to the queue. Returns false if it could not be saved on the phone
  /// (the caller must then keep the cart so nothing is lost).
  Future<bool> enqueue(PendingSale sale) async {
    _queue.add(sale);
    try {
      await _store.saveQueue(_queue);
    } catch (e) {
      debugPrint('Could not save the pending sale: $e');
      _queue.remove(sale);
      return false;
    }
    notifyListeners();
    return true;
  }

  /// Sends the waiting sales, oldest first. Stops at the first one that fails
  /// because of the connection. Returns how many reached the server.
  Future<int> sync() async {
    if (_syncing || _userId == null) return 0;
    if (_mine(_queue).isEmpty) return 0;

    _syncing = true;
    notifyListeners();
    var sent = 0;
    try {
      for (final sale in _mine(_queue)) {
        final result = await _api.submitCartSale(
          items: sale.items,
          receiptId: sale.receiptId,
          soldAt: sale.soldAt,
          offline: true,
        );
        if (result.outcome == SaleOutcome.network) break; // still no connection

        _queue.removeWhere((s) => s.receiptId == sale.receiptId);
        if (result.outcome == SaleOutcome.rejected) {
          _failed.add(sale.withError(result.message ?? 'The server refused this sale'));
        } else {
          sent++;
        }
        await _persist();
        notifyListeners();
      }
      if (sent > 0) {
        try {
          await _api.getProducts(); // refreshes the offline product list too
        } catch (_) {}
      }
    } finally {
      _syncing = false;
      if (sent > 0) syncedTick.value++;
      notifyListeners();
    }
    return sent;
  }

  /// Puts the refused sales back in the queue and tries again.
  Future<void> retryFailed() async {
    final uid = _userId;
    if (uid == null) return;
    final mine = _failed.where((s) => s.userId == uid).toList();
    if (mine.isEmpty) return;
    _failed.removeWhere((s) => s.userId == uid);
    _queue.addAll(mine.map((s) => s.withError(null)));
    await _persist();
    notifyListeners();
    await sync();
  }

  /// Deletes the refused sales from this phone.
  Future<void> discardFailed() async {
    final uid = _userId;
    _failed.removeWhere((s) => s.userId == uid);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _store.saveQueue(_queue);
      await _store.saveFailed(_failed);
    } catch (e) {
      debugPrint('Could not save the sale queue: $e');
    }
  }
}
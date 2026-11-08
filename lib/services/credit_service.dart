import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/credit.dart';

/// The server answered and said no (for example "insufficient stock").
/// Nothing was recorded.
class CreditRejected implements Exception {
  final String message;
  CreditRejected(this.message);
  @override
  String toString() => message;
}

/// Talks to the credit-book tables and functions (see credit_book.sql).
class CreditService {
  static final CreditService _instance = CreditService._();
  factory CreditService() => _instance;
  CreditService._();

  static const _timeout = Duration(seconds: 20);
  SupabaseClient get _c => Supabase.instance.client;

  /// The text to show for any error.
  static String message(Object e) => e is PostgrestException ? e.message : '$e';

  /// Everyone in the shop, A to Z (used to pick a customer at checkout).
  Future<List<Customer>> customers() async {
    final rows = await _c.from('sm_customers').select().order('name').timeout(_timeout);
    return [
      for (final r in rows as List) Customer.fromJson(Map<String, dynamic>.from(r as Map))
    ];
  }

  /// Customers with what each owes (owners only).
  Future<List<CustomerBalance>> balances() async {
    final rows = await _c.rpc('sm_customer_balances').timeout(_timeout);
    return [
      for (final r in rows as List)
        CustomerBalance.fromJson(Map<String, dynamic>.from(r as Map))
    ];
  }

  /// Adds a customer and returns it. The same phone number returns the existing one.
  Future<Customer> addCustomer(String name, String? phone) async {
    try {
      final id = await _c.rpc('sm_add_customer', params: {
        'p_name': name.trim(),
        'p_phone': (phone == null || phone.trim().isEmpty) ? null : phone.trim(),
      }).timeout(_timeout);
      return Customer(
        id: id as String,
        name: name.trim(),
        phone: (phone == null || phone.trim().isEmpty) ? null : phone.trim(),
      );
    } on PostgrestException catch (e) {
      throw CreditRejected(e.message);
    }
  }

  /// A customer's history, newest first.
  Future<List<CreditEntry>> entries(String customerId) async {
    final rows = await _c
        .from('sm_credit_entries')
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .timeout(_timeout);
    return [
      for (final r in rows as List) CreditEntry.fromJson(Map<String, dynamic>.from(r as Map))
    ];
  }

  /// Entries made between [from] and [to] (used by the daily summary). An owner
  /// gets the whole shop; a cashier only their own.
  Future<List<CreditEntry>> entriesBetween(DateTime from, DateTime to) async {
    final rows = await _c
        .from('sm_credit_entries')
        .select()
        .gte('created_at', from.toUtc().toIso8601String())
        .lt('created_at', to.toUtc().toIso8601String())
        .order('created_at')
        .timeout(_timeout);
    return [
      for (final r in rows as List) CreditEntry.fromJson(Map<String, dynamic>.from(r as Map))
    ];
  }

  /// Sells a cart on credit. Returns the order number. Sending the same
  /// [receiptId] twice records it only once. Throws [CreditRejected] when the
  /// server refuses; any other error means the result is unknown.
  Future<int?> creditSale({
    required List<Map<String, dynamic>> items,
    required String customerId,
    required String receiptId,
    required DateTime soldAt,
  }) async {
    try {
      final r = await _c.rpc('sm_record_credit_sale', params: {
        'p_items': items,
        'p_customer_id': customerId,
        'p_receipt_id': receiptId,
        'p_sold_at': soldAt.toUtc().toIso8601String(),
      }).timeout(_timeout);
      return (r as num?)?.toInt();
    } on PostgrestException catch (e) {
      throw CreditRejected(e.message);
    }
  }

  /// Records money received (owner only). Returns the new balance.
  Future<double> recordPayment(String customerId, double amount, {String? note}) async {
    try {
      final r = await _c.rpc('sm_record_credit_payment', params: {
        'p_customer_id': customerId,
        'p_amount': amount,
        'p_note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      }).timeout(_timeout);
      return (r as num).toDouble();
    } on PostgrestException catch (e) {
      throw CreditRejected(e.message);
    }
  }
}
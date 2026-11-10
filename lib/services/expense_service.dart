import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/expense.dart';

/// Shop expenses (owners only; the server refuses anyone else). See expenses.sql.
class ExpenseService {
  SupabaseClient get _c => Supabase.instance.client;
  static const _timeout = Duration(seconds: 20);

  /// Expenses with [from] <= spent date < [to], newest first.
  Future<List<Expense>> list(DateTime from, DateTime to) async {
    final r = await _c.rpc('sm_list_expenses', params: {
      'p_from': from.toUtc().toIso8601String(),
      'p_to': to.toUtc().toIso8601String(),
    }).timeout(_timeout);
    final rows = (r as List?) ?? const [];
    return [for (final e in rows) Expense.fromJson(Map<String, dynamic>.from(e as Map))];
  }

  /// [id] is made once on the phone, so sending the same expense again (after a
  /// weak connection) never records it twice.
  Future<void> add({
    required String id,
    required double amount,
    required String category,
    String? note,
    required DateTime spentAt,
  }) async {
    await _c.rpc('sm_add_expense', params: {
      'p_id': id,
      'p_amount': amount,
      'p_category': category,
      'p_note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      'p_spent_at': spentAt.toUtc().toIso8601String(),
    }).timeout(_timeout);
  }

  Future<void> delete(String id) async {
    await _c.rpc('sm_delete_expense', params: {'p_id': id}).timeout(_timeout);
  }
}
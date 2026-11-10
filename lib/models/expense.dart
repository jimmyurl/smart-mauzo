import 'package:flutter/material.dart';

/// A kind of shop cost. [key] is what is stored in the database (the server only
/// accepts these keys); [label] is English and is translated with tr() when shown.
class ExpenseCategory {
  final String key;
  final String label;
  final IconData icon;
  const ExpenseCategory(this.key, this.label, this.icon);
}

const List<ExpenseCategory> kExpenseCategories = [
  ExpenseCategory('rent', 'Rent', Icons.home_work_outlined),
  ExpenseCategory('salaries', 'Salaries', Icons.groups_outlined),
  ExpenseCategory('transport', 'Transport', Icons.local_shipping_outlined),
  ExpenseCategory('utilities', 'Electricity & water', Icons.bolt_outlined),
  ExpenseCategory('airtime', 'Airtime & internet', Icons.signal_cellular_alt),
  ExpenseCategory('licenses', 'Licenses & fees', Icons.assignment_outlined),
  ExpenseCategory('supplies', 'Supplies', Icons.inventory_2_outlined),
  ExpenseCategory('repairs', 'Repairs', Icons.build_outlined),
  ExpenseCategory('tax', 'Taxes', Icons.receipt_long_outlined),
  ExpenseCategory('other', 'Other', Icons.more_horiz),
];

ExpenseCategory expenseCategory(String key) => kExpenseCategories
    .firstWhere((c) => c.key == key, orElse: () => kExpenseCategories.last);

/// Money the shop spent (not goods bought for resale, which are tracked as stock).
class Expense {
  final String id;
  final double amount;
  final String category; // a key of kExpenseCategories
  final String? note;
  final DateTime spentAt;

  const Expense({
    required this.id,
    required this.amount,
    required this.category,
    required this.spentAt,
    this.note,
  });

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as String,
        amount: (j['amount'] as num).toDouble(),
        category: (j['category'] as String?) ?? 'other',
        note: j['note'] as String?,
        spentAt: DateTime.parse(j['spent_at'] as String),
      );
}
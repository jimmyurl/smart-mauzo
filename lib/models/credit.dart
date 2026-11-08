class Customer {
  final String id;
  final String name;
  final String? phone;
  const Customer({required this.id, required this.name, this.phone});

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String?,
      );
}

/// A customer and what they owe right now (owners only).
class CustomerBalance {
  final Customer customer;
  final double balance;
  final DateTime? lastActivity;
  const CustomerBalance({
    required this.customer,
    required this.balance,
    this.lastActivity,
  });

  factory CustomerBalance.fromJson(Map<String, dynamic> j) => CustomerBalance(
        customer: Customer(
          id: j['customer_id'] as String,
          name: j['customer_name'] as String,
          phone: j['customer_phone'] as String?,
        ),
        balance: (j['balance'] as num).toDouble(),
        lastActivity: j['last_activity'] == null
            ? null
            : DateTime.parse(j['last_activity'] as String),
      );
}

/// One line of a customer's history: goods taken on credit, or a payment.
class CreditEntry {
  final String id;
  final String customerId;
  final String kind; // 'sale' | 'payment'
  final double amount;
  final int? orderNo;
  final String? note;
  final String? createdBy;
  final DateTime createdAt;

  const CreditEntry({
    required this.id,
    required this.customerId,
    required this.kind,
    required this.amount,
    required this.createdAt,
    this.orderNo,
    this.note,
    this.createdBy,
  });

  bool get isSale => kind == 'sale';

  factory CreditEntry.fromJson(Map<String, dynamic> j) => CreditEntry(
        id: j['id'] as String,
        customerId: j['customer_id'] as String,
        kind: j['kind'] as String,
        amount: (j['amount'] as num).toDouble(),
        orderNo: (j['order_no'] as num?)?.toInt(),
        note: j['note'] as String?,
        createdBy: j['created_by'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
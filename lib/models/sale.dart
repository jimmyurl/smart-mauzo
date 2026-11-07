class Sale {
  final String id;
  final String productId;
  final String productTitle;
  final int quantity;
  final double total;
  final DateTime timestamp;
  final String paymentMethod; // 'cash' | 'mobile'

  /// Buying price per unit when the sale was made. 0 = unknown. Cashiers never
  /// receive it (their app asks the server for every column except this one).
  final double buyingPrice;

  /// The user who made the sale. Null for sales made before cashier accounts
  /// were tracked.
  final String? soldBy;

  Sale({
    required this.id,
    required this.productId,
    required this.productTitle,
    required this.quantity,
    required this.total,
    required this.timestamp,
    this.paymentMethod = 'cash',
    this.buyingPrice = 0,
    this.soldBy,
  });

  bool get isMobile => paymentMethod == 'mobile';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_title': productTitle,
      'quantity': quantity,
      'total': total,
      'timestamp': timestamp.toIso8601String(),
      'payment_method': paymentMethod,
      'buying_price': buyingPrice,
      'sold_by': soldBy,
    };
  }

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'],
      productId: json['product_id'],
      productTitle: json['product_title'],
      quantity: json['quantity'],
      total: (json['total'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
      paymentMethod: json['payment_method'] ?? 'cash',
      buyingPrice: (json['buying_price'] as num?)?.toDouble() ?? 0,
      soldBy: json['sold_by'] as String?,
    );
  }
}
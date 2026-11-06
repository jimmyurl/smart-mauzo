class Sale {
  final String id;
  final String productId;
  final String productTitle;
  final int quantity;
  final double total;
  final DateTime timestamp;
  final String paymentMethod; // 'cash' | 'mobile'
  final double buyingPrice; // cost per unit at the moment of sale

  Sale({
    required this.id,
    required this.productId,
    required this.productTitle,
    required this.quantity,
    required this.total,
    required this.timestamp,
    this.paymentMethod = 'cash',
    this.buyingPrice = 0,
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
      buyingPrice: double.tryParse('${json['buying_price'] ?? 0}') ?? 0,
    );
  }
}
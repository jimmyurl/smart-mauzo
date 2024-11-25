class Sale {
  final String id;
  final String productId;
  final String productTitle;
  final int quantity;
  final double total;
  final DateTime timestamp;

  Sale({
    required this.id,
    required this.productId,
    required this.productTitle,
    required this.quantity,
    required this.total,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_title': productTitle,
      'quantity': quantity,
      'total': total,
      'timestamp': timestamp.toIso8601String(),
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
    );
  }
}

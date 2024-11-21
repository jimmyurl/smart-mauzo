import 'package:flutter/foundation.dart';

@immutable
class Sale {
  final String id;
  final String productId;
  final String productTitle;
  final int quantity;
  final double total;
  final DateTime timestamp;

  const Sale({
    required this.id,
    required this.productId,
    required this.productTitle,
    required this.quantity,
    required this.total,
    required this.timestamp,
  });

  // Optional: Factory constructor to create a Sale from a JSON map
  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'].toString(),
      productId: json['product_id'].toString(),
      productTitle:
          json['product_title'] ?? '', // Ensure a default value if null
      quantity: json['quantity'] as int,
      total: (json['total_price'] as num).toDouble(),
      timestamp: DateTime.parse(json['sale_date']),
    );
  }

  // Optional: Method to convert Sale to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_title': productTitle,
      'quantity': quantity,
      'total_price': total,
      'sale_date': timestamp.toIso8601String(),
    };
  }
}

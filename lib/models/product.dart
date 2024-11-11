import 'package:flutter/foundation.dart';

class Product {
  final String id;
  final String barcode;
  final String name;
  final double price;
  int stockQuantity;
  DateTime? createdAt;
  DateTime? updatedAt;

  Product({
    required this.id,
    required this.barcode,
    required this.name,
    required this.price,
    required this.stockQuantity,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'price': price,
      'stock_quantity': stockQuantity,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory Product.fromJson(Map<String, dynamic> map) {
    return Product(
      id: map['id'] ?? '',
      barcode: map['barcode'] ?? '',
      name: map['name'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      stockQuantity: map['stock_quantity'] ?? 0,
      createdAt:
          map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      updatedAt:
          map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
    );
  }
}

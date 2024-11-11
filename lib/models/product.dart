class Product {
  final String id;
  final String title;
  final String? description;
  final double price;
  final String? imageUrl;
  final String barcode;
  int stockQuantity;
  final DateTime createdAt;

  Product({
    required this.id,
    required this.title,
    this.description,
    required this.price,
    this.imageUrl,
    required this.barcode,
    required this.stockQuantity,
    required this.createdAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      price: double.parse(json['price'].toString()),
      imageUrl: json['image_url'],
      barcode: json['barcode'] ?? '',
      stockQuantity: json['stock_quantity'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'barcode': barcode,
      'stock_quantity': stockQuantity,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

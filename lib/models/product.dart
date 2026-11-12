import 'product_unit.dart';

class Product {
  final String id;
  final String title;
  final String? description;
  final double price;
  final double buyingPrice; // cost per item (what the shop pays suppliers)
  final String? imageUrl;
  final String barcode;
  int stockQuantity;
  final DateTime createdAt;
  final String? category; // NEW
  final DateTime? expiryDate; // optional, date only

  /// Optional prices for other kinds of customer (null = use the retail [price]).
  final double? priceWholesale;
  final double? priceSpecial;

  /// What one item is called, e.g. "tablet" or "bag". Optional.
  final String? baseUnit;

  /// Bigger units (strip, box, tonne...). Stock is always counted in base units.
  List<ProductUnit> units;

  Product({
    required this.id,
    required this.title,
    this.description,
    required this.price,
    this.buyingPrice = 0,
    this.imageUrl,
    required this.barcode,
    required this.stockQuantity,
    required this.createdAt,
    this.category, // NEW
    this.expiryDate,
    this.priceWholesale,
    this.priceSpecial,
    this.baseUnit,
    List<ProductUnit>? units,
  }) : units = units ?? <ProductUnit>[];

  /// Price of ONE [unit] (null = the base unit) at a price [level]. Missing level
  /// prices fall back to retail; the server uses the same rules.
  double priceFor(String level, {ProductUnit? unit}) {
    if (unit != null) return unit.priceFor(level, price);
    if (level == 'wholesale') return priceWholesale ?? price;
    if (level == 'special') return priceSpecial ?? price;
    return price;
  }

  /// Whole days from today until the expiry date (negative = already expired).
  /// Null when no expiry date is set.
  int? get daysToExpiry {
    final e = expiryDate;
    if (e == null) return null;
    final now = DateTime.now();
    return DateTime(e.year, e.month, e.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      price: double.parse(json['price'].toString()),
      buyingPrice: double.tryParse('${json['buying_price'] ?? 0}') ?? 0,
      imageUrl: json['image_url'],
      barcode: json['barcode'] ?? '',
      stockQuantity: json['stock_quantity'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
      category: json['category'], // NEW
      expiryDate: json['expiry_date'] == null
          ? null
          : DateTime.tryParse('${json['expiry_date']}'),
      priceWholesale: json['price_wholesale'] == null
          ? null
          : double.tryParse('${json['price_wholesale']}'),
      priceSpecial: json['price_special'] == null
          ? null
          : double.tryParse('${json['price_special']}'),
      baseUnit: json['unit_name'] as String?,
      units: [
        for (final u in (json['units'] as List? ?? const []))
          ProductUnit.fromJson(Map<String, dynamic>.from(u as Map)),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'price': price,
      'buying_price': buyingPrice,
      'image_url': imageUrl,
      'barcode': barcode,
      'stock_quantity': stockQuantity,
      'created_at': createdAt.toIso8601String(),
      'category': category, // NEW
      'price_wholesale': priceWholesale,
      'price_special': priceSpecial,
      'unit_name': baseUnit,
      'units': [for (final u in units) u.toJson()],
      'expiry_date': expiryDate == null
          ? null
          : '${expiryDate!.year.toString().padLeft(4, '0')}-'
              '${expiryDate!.month.toString().padLeft(2, '0')}-'
              '${expiryDate!.day.toString().padLeft(2, '0')}',
    };
  }
}
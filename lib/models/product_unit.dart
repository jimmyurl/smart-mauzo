/// The three prices a shop can charge. Retail is the product's normal price.
const List<String> kPriceLevels = ['retail', 'wholesale', 'special'];

/// English name (the screen passes it through tr()).
String priceLevelLabel(String level) =>
    level == 'wholesale' ? 'Wholesale' : (level == 'special' ? 'Special' : 'Retail');

double? _asDouble(dynamic v) => v == null ? null : double.tryParse('$v');

/// A bigger unit of a product, e.g. 1 strip = 10 tablets. Stock is always counted
/// in the product's base unit; [factor] says how many base units one of these holds.
class ProductUnit {
  final String id;
  final String productId;
  final String name;
  final int factor; // base units in one of these (2 or more)
  final double? price; // retail price of one; null = product price x factor
  final double? priceWholesale;
  final double? priceSpecial;

  const ProductUnit({
    required this.id,
    required this.productId,
    required this.name,
    required this.factor,
    this.price,
    this.priceWholesale,
    this.priceSpecial,
  });

  /// Price of ONE of this unit at [level]. [baseRetail] is the product's retail price
  /// per base unit. The same rules run on the server (see units_price_levels.sql).
  double priceFor(String level, double baseRetail) {
    final specific = level == 'wholesale' ? priceWholesale : (level == 'special' ? priceSpecial : null);
    return specific ?? price ?? baseRetail * factor;
  }

  factory ProductUnit.fromJson(Map<String, dynamic> j) => ProductUnit(
        id: j['id'] as String,
        productId: j['product_id'] as String,
        name: j['name'] as String,
        factor: (j['factor'] as num).toInt(),
        price: _asDouble(j['price']),
        priceWholesale: _asDouble(j['price_wholesale']),
        priceSpecial: _asDouble(j['price_special']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'name': name,
        'factor': factor,
        'price': price,
        'price_wholesale': priceWholesale,
        'price_special': priceSpecial,
      };
}
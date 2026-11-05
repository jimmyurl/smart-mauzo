import '../models/product.dart';

const String kUncategorized = 'Uncategorized';

/// Category of a product, falling back to "Uncategorized" when empty.
String categoryOf(Product p) {
  final c = p.category?.trim();
  return (c == null || c.isEmpty) ? kUncategorized : c;
}

/// Groups products by category. Categories are sorted A-Z ("Uncategorized" last),
/// and products inside each category are sorted A-Z.
Map<String, List<Product>> groupByCategory(Iterable<Product> products) {
  final map = <String, List<Product>>{};
  for (final p in products) {
    map.putIfAbsent(categoryOf(p), () => []).add(p);
  }
  for (final list in map.values) {
    list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }
  final keys = map.keys.toList()
    ..sort((a, b) {
      if (a == kUncategorized) return 1;
      if (b == kUncategorized) return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  return {for (final k in keys) k: map[k]!};
}
import 'sale.dart';

/// "#0012" for order 12.
String orderLabel(int orderNo) => '#${orderNo.toString().padLeft(4, '0')}';

/// One order = everything sold in one checkout. The database stores one row per
/// product (a "line"); all the lines of an order share the same order number.
class Order {
  /// The lines of this order, in the order they were received.
  final List<Sale> lines;

  /// Credit sales only: money the customer paid at the counter (a deposit).
  /// Not stored on the sale rows; it is known right after the sale so the
  /// receipt can show "Paid now / Balance owed".
  final double paidNow;

  Order(this.lines, {this.paidNow = 0});

  Sale get first => lines.first;
  int? get orderNo => first.orderNo;

  /// "#0012", or null for a sale that has no number yet.
  String? get number => orderNo == null ? null : orderLabel(orderNo!);

  DateTime get time => first.timestamp;
  String? get soldBy => first.soldBy;
  bool get isMobile => lines.any((l) => l.isMobile);
  bool get isCredit => lines.any((l) => l.isCredit);
  bool get isOwnTill => lines.any((l) => l.isOwnTill);
  PayMethod get method => isCredit
      ? PayMethod.credit
      : (isOwnTill ? PayMethod.lipa : (isMobile ? PayMethod.mobile : PayMethod.cash));

  /// "Cash", "On credit", "Mobile / Card" or "Mobile money (M-Pesa) - Ref ...".
  String get paymentLabel {
    if (isCredit) return 'On credit';
    for (final l in lines) {
      if (l.isOwnTill) return l.paymentLabel;
    }
    return isMobile ? 'Mobile / Card' : 'Cash';
  }
  bool get isSingle => lines.length == 1;

  int get productCount => lines.length;
  int get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);
  double get total => lines.fold(0.0, (sum, l) => sum + l.total);

  /// Groups sales into orders. Keeps the order in which orders first appear
  /// (so a newest-first list stays newest first).
  static List<Order> group(Iterable<Sale> sales) {
    final byKey = <String, List<Sale>>{};
    for (final s in sales) {
      final key = s.orderNo != null ? 'n${s.orderNo}' : 'i${s.id}';
      byKey.putIfAbsent(key, () => []).add(s);
    }
    return [
      for (final lines in byKey.values)
        Order(lines..sort((a, b) => a.productTitle.compareTo(b.productTitle)))
    ];
  }
}
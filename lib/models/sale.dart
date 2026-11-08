enum PayMethod { cash, mobile, credit }

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

  /// The shop's running order number (1, 2, 3 ...). Every item of one order has
  /// the same number. Null only for a sale the server has not numbered yet.
  final int? orderNo;

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
    this.orderNo,
  });

  bool get isMobile => paymentMethod == 'mobile';

  /// Taken on credit (the customer owes the money). The server stores these
  /// like cash sales; the app marks them by looking at the credit book.
  bool get isCredit => paymentMethod == 'credit';

  PayMethod get method =>
      isCredit ? PayMethod.credit : (isMobile ? PayMethod.mobile : PayMethod.cash);

  Sale withPaymentMethod(String method) => Sale(
        id: id,
        productId: productId,
        productTitle: productTitle,
        quantity: quantity,
        total: total,
        timestamp: timestamp,
        paymentMethod: method,
        buyingPrice: buyingPrice,
        soldBy: soldBy,
        orderNo: orderNo,
      );

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
      'order_no': orderNo,
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
      orderNo: (json['order_no'] as num?)?.toInt(),
    );
  }
}
enum PayMethod { cash, mobile, lipa, credit }

/// Mobile-money networks a shop can be paid on directly (own till / Lipa number),
/// without Pesapal. key -> name shown to people. Keys are stored in the database.
const Map<String, String> kMobileProviders = {
  'mpesa': 'M-Pesa',
  'tigopesa': 'Mixx by Yas (Tigo Pesa)',
  'airtel': 'Airtel Money',
  'halopesa': 'HaloPesa',
  'tpesa': 'T-Pesa',
  'other': 'Other',
};

String providerLabel(String? key) => kMobileProviders[key] ?? (key ?? '');

class Sale {
  final String id;
  final String productId;
  final String productTitle;
  final int quantity;
  final double total;
  final DateTime timestamp;
  final String paymentMethod; // 'cash' | 'mobile' (Pesapal) | 'lipa' (own till) | 'credit'

  /// Only for 'lipa' sales: which network the customer paid on (a key of
  /// [kMobileProviders]) and the transaction reference from the SMS (optional).
  final String? payProvider;
  final String? payRef;

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
    this.payProvider,
    this.payRef,
    this.buyingPrice = 0,
    this.soldBy,
    this.orderNo,
  });

  /// Paid with mobile money straight to the shop's own number (no gateway).
  bool get isOwnTill => paymentMethod == 'lipa';

  /// Any digital payment (Pesapal or the shop's own till). Totals treat both alike.
  bool get isMobile => paymentMethod == 'mobile' || paymentMethod == 'lipa';

  /// Taken on credit (the customer owes the money). The server stores these
  /// like cash sales; the app marks them by looking at the credit book.
  bool get isCredit => paymentMethod == 'credit';

  PayMethod get method => isCredit
      ? PayMethod.credit
      : (isOwnTill ? PayMethod.lipa : (isMobile ? PayMethod.mobile : PayMethod.cash));

  /// Text for receipts and details, e.g. "Mobile money (M-Pesa) - Ref QJ81ABC".
  String get paymentLabel {
    if (isCredit) return 'On credit';
    if (isOwnTill) {
      final p = payProvider == null ? '' : ' (${providerLabel(payProvider)})';
      final r = (payRef == null || payRef!.isEmpty) ? '' : ' - Ref $payRef';
      return 'Mobile money$p$r';
    }
    return isMobile ? 'Mobile / Card' : 'Cash';
  }

  Sale withPaymentMethod(String method) => Sale(
        id: id,
        productId: productId,
        productTitle: productTitle,
        quantity: quantity,
        total: total,
        timestamp: timestamp,
        paymentMethod: method,
        payProvider: payProvider,
        payRef: payRef,
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
      'pay_provider': payProvider,
      'pay_ref': payRef,
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
      payProvider: json['pay_provider'] as String?,
      payRef: json['pay_ref'] as String?,
      buyingPrice: (json['buying_price'] as num?)?.toDouble() ?? 0,
      soldBy: json['sold_by'] as String?,
      orderNo: (json['order_no'] as num?)?.toInt(),
    );
  }
}
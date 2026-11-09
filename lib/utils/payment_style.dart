import 'package:flutter/material.dart';

import '../models/sale.dart';

const Color kCashColor = Color(0xFF2E7D32);
const Color kMobileColor = Color(0xFF1565C0);
const Color kCreditColor = Color(0xFFEF6C00);
const Color kLipaColor = Color(0xFF00897B);

/// How a payment method looks everywhere in the app.
extension PayMethodStyle on PayMethod {
  String get label {
    if (this == PayMethod.credit) return 'Credit';
    if (this == PayMethod.lipa) return 'Mobile money';
    if (this == PayMethod.mobile) return 'Mobile/Card';
    return 'Cash';
  }

  Color get color {
    if (this == PayMethod.credit) return kCreditColor;
    if (this == PayMethod.lipa) return kLipaColor;
    if (this == PayMethod.mobile) return kMobileColor;
    return kCashColor;
  }

  IconData get icon {
    if (this == PayMethod.credit) return Icons.menu_book_outlined;
    if (this == PayMethod.lipa) return Icons.account_balance_wallet_outlined;
    if (this == PayMethod.mobile) return Icons.smartphone;
    return Icons.payments;
  }
}
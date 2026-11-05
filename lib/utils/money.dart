import 'package:intl/intl.dart';

final NumberFormat _tzs = NumberFormat('#,##0');

/// 15000 -> "TZS 15,000"
String tzs(num value) => 'TZS ${_tzs.format(value)}';
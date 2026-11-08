import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order.dart';
import '../utils/money.dart';
import 'shop_service.dart';

/// Builds a receipt for one order, as text (WhatsApp / SMS) and as a PDF
/// (share or print). Works from the order's own data, so it needs no internet
/// once the shop name has been saved on the phone.
class ReceiptService {
  static const _kShopName = 'sm_shop_name_v1';
  static const _fallbackName = 'Smart Mauzo';

  /// The shop name for the receipt header. Asks the server when it can and
  /// remembers the answer, so receipts still carry the name offline.
  static Future<String> shopName() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final shop = await ShopService().myShop().timeout(const Duration(seconds: 4));
      final name = shop?.name.trim() ?? '';
      if (name.isNotEmpty) {
        await prefs.setString(_kShopName, name);
        return name;
      }
    } catch (_) {}
    return prefs.getString(_kShopName) ?? _fallbackName;
  }

  static String _when(Order o) =>
      DateFormat('dd MMM yyyy, HH:mm').format(o.time.toLocal());

  static String _unit(double total, int qty) => tzs(qty > 0 ? total / qty : total);

  static String _payment(Order o) => o.isMobile ? 'Mobile / Card' : 'Cash';

  /// Plain text. *Stars* make the shop name bold in WhatsApp.
  static String buildText(Order order, {required String shopName, String? servedBy}) {
    const line = '--------------------';
    final b = StringBuffer()
      ..writeln('*$shopName*')
      ..writeln(order.number == null ? 'Receipt' : 'Order ${order.number}')
      ..writeln(_when(order));
    if (servedBy != null && servedBy.isNotEmpty) b.writeln('Served by: $servedBy');
    b.writeln(line);
    for (final l in order.lines) {
      b
        ..writeln(l.productTitle)
        ..writeln('  ${l.quantity} x ${_unit(l.total, l.quantity)} = ${tzs(l.total)}');
    }
    b
      ..writeln(line)
      ..writeln('*TOTAL: ${tzs(order.total)}*')
      ..writeln('Paid: ${_payment(order)}')
      ..writeln()
      ..write('Thank you for shopping with us!');
    return b.toString();
  }

  /// A narrow 80 mm "roll" receipt that fits a thermal printer or a phone screen.
  static Future<Uint8List> buildPdf(Order order,
      {required String shopName, String? servedBy}) async {
    final doc = pw.Document();
    pw.Widget center(String t, {double size = 10, bool bold = false}) => pw.Center(
          child: pw.Text(t,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  fontSize: size,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );
    pw.Widget rule() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          child: pw.Divider(thickness: 0.5, height: 1),
        );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            center(shopName, size: 14, bold: true),
            pw.SizedBox(height: 2),
            center(order.number == null ? 'Receipt' : 'Order ${order.number}', bold: true),
            center(_when(order), size: 9),
            if (servedBy != null && servedBy.isNotEmpty)
              center('Served by: $servedBy', size: 9),
            rule(),
            for (final l in order.lines)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(l.productTitle, style: const pw.TextStyle(fontSize: 10)),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('  ${l.quantity} x ${_unit(l.total, l.quantity)}',
                            style: const pw.TextStyle(fontSize: 9)),
                        pw.Text(tzs(l.total), style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
            rule(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOTAL',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text(tzs(order.total),
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 2),
            center('Paid: ${_payment(order)}', size: 9),
            pw.SizedBox(height: 10),
            center('Thank you for shopping with us!', size: 9),
          ],
        ),
      ),
    );
    return doc.save();
  }
}

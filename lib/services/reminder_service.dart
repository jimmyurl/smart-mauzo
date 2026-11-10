import 'dart:io' show Platform;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/money.dart';
import '../utils/phone_auth.dart';

/// Debt reminders sent to a customer by WhatsApp or SMS. Nothing is sent from
/// the server: the owner's own phone opens WhatsApp / the SMS app with the
/// message ready, so it costs nothing and comes from the shop's own number.
class ReminderService {
  static const _kPayInfo = 'sm_reminder_pay_info_v1';
  static String _kLast(String customerId) => 'sm_reminded_$customerId';

  /// Digits-only international number (255712345678), or null if the customer
  /// has no usable phone number.
  static String? whatsappNumber(String? phone) {
    if (phone == null || phone.trim().isEmpty) return null;
    return PhoneAuth.normalize(phone);
  }

  static String buildMessage({
    required bool swahili,
    required String shopName,
    required String customerName,
    required double balance,
    String payInfo = '',
  }) {
    final amount = tzs(balance);
    final pay = payInfo.trim();
    if (swahili) {
      return 'Habari $customerName, hiki ni kumbusho kutoka $shopName. '
          'Deni lako ni $amount. Tafadhali lipa mapema uwezavyo.'
          '${pay.isEmpty ? '' : ' Lipa kwa: $pay.'} Asante!';
    }
    return 'Hello $customerName, this is a friendly reminder from $shopName. '
        'Your outstanding balance is $amount. Please pay when you can.'
        '${pay.isEmpty ? '' : ' Pay to: $pay.'} Thank you!';
  }

  /// How the shop wants to be paid, e.g. "Lipa 5123456 (M-Pesa)". Remembered.
  static Future<String> payInfo() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_kPayInfo) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> savePayInfo(String value) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_kPayInfo, value.trim());
    } catch (_) {}
  }

  static Future<DateTime?> lastReminded(String customerId) async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_kLast(customerId));
      return v == null ? null : DateTime.tryParse(v);
    } catch (_) {
      return null;
    }
  }

  static Future<void> markReminded(String customerId) async {
    try {
      await (await SharedPreferences.getInstance())
          .setString(_kLast(customerId), DateTime.now().toIso8601String());
    } catch (_) {}
  }

  static Future<bool> openWhatsApp(String number, String text) async {
    try {
      return await launchUrl(
        Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openSms(String number, String text) async {
    final sep = Platform.isIOS ? '&' : '?';
    try {
      return await launchUrl(Uri.parse('sms:+$number${sep}body=${Uri.encodeComponent(text)}'));
    } catch (_) {
      return false;
    }
  }
}
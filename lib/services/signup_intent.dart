import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers that this account signed up as a CASHIER (with the owner's shop
/// code), so the app never offers it the "Create shop" option.
class SignupIntent {
  static const _key = 'sm_cashier_uid_v1';
  static String? _cashierUid;
  static bool _pending = false; // signing up as a cashier right now
  static bool _loaded = false;

  /// Reads the saved value. Safe to call many times.
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _cashierUid = prefs.getString(_key);
    } catch (e) {
      debugPrint('Could not read the cashier flag: $e');
    }
    _loaded = true;
  }

  /// Call just BEFORE signing up as a cashier: the app switches to the
  /// join-only screen the moment the new account is signed in.
  static void expectCashier() => _pending = true;

  /// Call if the sign-up failed.
  static void cancelPending() => _pending = false;

  static bool isCashier(String? uid) =>
      _pending || (uid != null && uid == _cashierUid);

  /// Call once the new account exists.
  static Future<void> markCashier(String uid) async {
    _cashierUid = uid;
    _pending = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, uid);
    } catch (e) {
      debugPrint('Could not save the cashier flag: $e');
    }
  }
}
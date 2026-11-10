import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum RecoveryResult { ok, invalid, locked, weak }

/// Password recovery without SMS or email.
///
/// An owner has a private recovery code (10 characters, shown once). Forgotten
/// password: phone number + recovery code + new password. The code is kept only
/// as a hash on the server, and wrong tries are limited there
/// (see password_recovery.sql).
class RecoveryService {
  static SupabaseClient get _c => Supabase.instance.client;
  static const _timeout = Duration(seconds: 20);
  static const _kSnooze = 'sm_recovery_nudge_until_v1';

  /// True for a phone + password account (owners, older phone cashiers). Cashiers
  /// who log in with a code have no password to recover.
  static bool get isPhoneAccount =>
      RegExp(r'^[0-9]{10,15}@').hasMatch(_c.auth.currentUser?.email ?? '');

  static Future<bool> hasCode() async {
    final r = await _c.rpc('sm_has_recovery_code').timeout(_timeout);
    return r == true;
  }

  /// Makes a new code (the old one stops working). Returns it as XXXXX-XXXXX.
  /// This is the only time it can be seen.
  static Future<String> createCode() async {
    final r = await _c.rpc('sm_create_recovery_code').timeout(_timeout);
    return r as String;
  }

  /// Works while logged out. [phone] must already be normalized (255712345678).
  static Future<RecoveryResult> resetPassword({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    final r = await _c.rpc('sm_reset_password_with_code', params: {
      'p_phone': phone,
      'p_code': code,
      'p_new_password': newPassword,
    }).timeout(_timeout);
    switch (r) {
      case 'ok':
        return RecoveryResult.ok;
      case 'locked':
        return RecoveryResult.locked;
      case 'weak':
        return RecoveryResult.weak;
      default:
        return RecoveryResult.invalid;
    }
  }

  /// Logged-in password change. Checks the current password first.
  /// Throws [AuthException] if the current password is wrong.
  static Future<void> changePassword({
    required String current,
    required String newPassword,
  }) async {
    final email = _c.auth.currentUser?.email;
    if (email == null) throw StateError('not signed in');
    await _c.auth.signInWithPassword(email: email, password: current).timeout(_timeout);
    await _c.auth.updateUser(UserAttributes(password: newPassword)).timeout(_timeout);
  }

  // The "create a recovery code" reminder is not shown again for a few days after "Later".
  static Future<bool> nudgeSnoozed() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_kSnooze);
      final until = v == null ? null : DateTime.tryParse(v);
      return until != null && until.isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  static Future<void> snoozeNudge() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
          _kSnooze, DateTime.now().add(const Duration(days: 3)).toIso8601String());
    } catch (_) {}
  }
}
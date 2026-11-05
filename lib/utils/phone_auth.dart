/// Phone-number login without SMS.
///
/// Supabase needs an email or phone to identify an account. To avoid SMS
/// fees, the phone number is turned into a private, never-mailed login
/// address such as 255712345678@phone.smartmauzo.app and the person signs in
/// with phone + password. Requires "Confirm email" to be OFF in
/// Supabase -> Authentication -> Providers -> Email.
class PhoneAuth {
  static const String _domain = 'smartflow.co.tz';
  static const String _defaultCountryCode = '255'; // Tanzania

  /// Returns digits-only international form (e.g. 255712345678), or null if
  /// the number does not look valid.
  ///
  /// Accepts: 0712 345 678, 712345678, +255712345678, 255712345678,
  /// and other countries when typed with a leading + (e.g. +254712345678).
  static String? normalize(String input) {
    var s = input.trim();
    final international = s.startsWith('+');
    s = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (s.isEmpty) return null;

    if (international) {
      // keep as typed
    } else if (s.startsWith('00')) {
      s = s.substring(2);
    } else if (s.startsWith('0')) {
      s = _defaultCountryCode + s.substring(1);
    } else if (s.startsWith(_defaultCountryCode)) {
      // already has the country code
    } else if (s.length == 9) {
      s = _defaultCountryCode + s;
    }

    if (s.length < 10 || s.length > 15) return null;
    if (s.startsWith(_defaultCountryCode) && s.length != 12) return null;
    return s;
  }

  /// The hidden login address for a normalized phone number.
  static String emailFor(String normalizedPhone) => '$normalizedPhone@$_domain';

  /// Shows a login address back as a phone number, e.g. +255712345678.
  /// Returns null if the address is not a phone login.
  static String? phoneFromEmail(String? email) {
    if (email == null || !email.endsWith('@$_domain')) return null;
    return '+${email.substring(0, email.length - _domain.length - 1)}';
  }
}
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/phone_auth.dart';

class ShopInfo {
  final String id;
  final String name;
  final String role; // 'owner' | 'cashier'
  final String? joinCode; // only present for owners
  ShopInfo({
    required this.id,
    required this.name,
    required this.role,
    this.joinCode,
    this.isSuperAdmin = false,
  });

  final bool isSuperAdmin;

  bool get isOwner => role == 'owner';

  factory ShopInfo.fromJson(Map<String, dynamic> j) => ShopInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        role: j['role'] as String,
        joinCode: j['join_code'] as String?,
        isSuperAdmin: (j['is_super_admin'] as bool?) ?? false,
      );
}

/// Login + shop membership. All security is enforced in Supabase (row-level security),
/// this class only calls it.
class ShopService {
  SupabaseClient get _c => Supabase.instance.client;

  Session? get session => _c.auth.currentSession;
  String? get email => _c.auth.currentUser?.email;
  Stream<AuthState> get authChanges => _c.auth.onAuthStateChange;

  Future<void> signIn(String email, String password) =>
      _c.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUp(String email, String password) =>
      _c.auth.signUp(email: email, password: password);

  /// Phone + password login. [phone] can be typed any normal way (0712..., +255712...).
  /// Throws [FormatException] if the number is not valid.
  Future<void> signInWithPhone(String phone, String password) {
    final p = PhoneAuth.normalize(phone);
    if (p == null) throw const FormatException('Enter a valid phone number');
    return signIn(PhoneAuth.emailFor(p), password);
  }

  Future<AuthResponse> signUpWithPhone(String phone, String password) {
    final p = PhoneAuth.normalize(phone);
    if (p == null) throw const FormatException('Enter a valid phone number');
    return signUp(PhoneAuth.emailFor(p), password);
  }

  /// The signed-in person's phone number (or email for older email accounts).
  String? get phoneOrEmail => PhoneAuth.phoneFromEmail(email) ?? email;

  Future<void> signOut() => _c.auth.signOut();

  /// The shop the signed-in user belongs to, or null if they have not created/joined one yet.
  Future<ShopInfo?> myShop() async {
    final r = await _c.rpc('sm_my_shop');
    if (r == null) return null;
    return ShopInfo.fromJson(Map<String, dynamic>.from(r as Map));
  }

  Future<void> createShop(String name) => _c.rpc('sm_create_shop', params: {'p_name': name});

  Future<void> joinShop(String code) => _c.rpc('sm_join_shop', params: {'p_code': code});
}
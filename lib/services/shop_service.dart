import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/phone_auth.dart';
import 'offline_store.dart';

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

/// One person in the owner's shop (from sm_shop_team, owners only).
class TeamMember {
  final String userId;
  final String email; // for phone accounts this is a made-up address, see [label]
  final String role; // 'owner' | 'cashier'
  final DateTime joinedAt;
  final int salesCount; // number of sales (a whole cart counts once)
  final double salesTotal;
  final DateTime? lastSale;

  TeamMember({
    required this.userId,
    required this.email,
    required this.role,
    required this.joinedAt,
    required this.salesCount,
    required this.salesTotal,
    this.lastSale,
  });

  bool get isOwner => role == 'owner';

  /// What to show as the person's name: their phone number (or email).
  String get label => PhoneAuth.phoneFromEmail(email) ?? email;

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        userId: j['user_id'] as String,
        email: (j['email'] as String?) ?? '',
        role: j['role'] as String,
        joinedAt: DateTime.parse(j['joined_at'] as String),
        salesCount: (j['sales_count'] as num?)?.toInt() ?? 0,
        salesTotal: (j['sales_total'] as num?)?.toDouble() ?? 0,
        lastSale: j['last_sale'] == null ? null : DateTime.parse(j['last_sale'] as String),
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
    final shop = ShopInfo.fromJson(Map<String, dynamic>.from(r as Map));
    // Remember the role so owner-only screens also work without internet.
    final uid = _c.auth.currentUser?.id;
    if (uid != null) OfflineIdentity.setRole(uid, shop.role);
    return shop;
  }

  /// Everyone in the owner's shop with their sales totals (owner only).
  Future<List<TeamMember>> team() async {
    final rows = await _c.rpc('sm_shop_team');
    return [
      for (final r in rows as List) TeamMember.fromJson(Map<String, dynamic>.from(r as Map))
    ];
  }

  /// Takes a cashier out of the shop. Their past sales stay in the records.
  Future<void> removeMember(String userId) =>
      _c.rpc('sm_remove_member', params: {'p_user_id': userId});

  /// Replaces the shop code; the old one stops working. Returns the new code.
  Future<String> newJoinCode() async {
    final r = await _c.rpc('sm_new_join_code');
    return r as String;
  }

  Future<void> createShop(String name) => _c.rpc('sm_create_shop', params: {'p_name': name});

  Future<void> joinShop(String code) => _c.rpc('sm_join_shop', params: {'p_code': code});
}
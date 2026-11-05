import 'package:supabase_flutter/supabase_flutter.dart';

class ShopInfo {
  final String id;
  final String name;
  final String role; // 'owner' | 'cashier'
  final String? joinCode; // only present for owners
  ShopInfo({required this.id, required this.name, required this.role, this.joinCode});

  bool get isOwner => role == 'owner';

  factory ShopInfo.fromJson(Map<String, dynamic> j) => ShopInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        role: j['role'] as String,
        joinCode: j['join_code'] as String?,
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

  Future<void> signOut() => _c.auth.signOut();

  /// The shop the signed-in user belongs to, or null if they have not created/joined one yet.
  Future<ShopInfo?> myShop() async {
    final r = await _c.rpc('my_shop');
    if (r == null) return null;
    return ShopInfo.fromJson(Map<String, dynamic>.from(r as Map));
  }

  Future<void> createShop(String name) => _c.rpc('create_shop', params: {'p_name': name});

  Future<void> joinShop(String code) => _c.rpc('join_shop', params: {'p_code': code});
}
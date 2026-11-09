import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../utils/phone_auth.dart';
import 'offline_store.dart';
import 'signup_intent.dart';

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

/// The shop, and whether it is the live answer or the copy saved on this phone.
class ShopLoad {
  final ShopInfo? shop;
  final bool fromCache;
  const ShopLoad(this.shop, this.fromCache);
}

/// One person in the owner's shop (from sm_shop_team, owners only).
class TeamMember {
  final String? userId; // null until a cashier has logged in once
  final String? name; // the name the owner gave a cashier
  final String? email; // older phone-number accounts only
  final String role; // 'owner' | 'cashier'
  final DateTime joinedAt;
  final int salesCount; // number of sales (a whole cart counts once)
  final double salesTotal;
  final DateTime? lastSale;
  final String? code; // the cashier's login code (null for older accounts)
  final bool claimed; // has logged in at least once

  TeamMember({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.joinedAt,
    required this.salesCount,
    required this.salesTotal,
    required this.lastSale,
    required this.code,
    required this.claimed,
  });

  bool get isOwner => role == 'owner';

  /// What to show as the person's name.
  String get label =>
      name ?? PhoneAuth.phoneFromEmail(email) ?? email ?? 'Cashier';

  /// "ABCD-EFGH" is easier to read out and type than "ABCDEFGH".
  String? get prettyCode =>
      code == null ? null : '${code!.substring(0, 4)}-${code!.substring(4)}';

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        userId: j['user_id'] as String?,
        name: j['name'] as String?,
        email: j['email'] as String?,
        role: j['role'] as String,
        joinedAt: DateTime.parse(j['joined_at'] as String),
        salesCount: (j['sales_count'] as num?)?.toInt() ?? 0,
        salesTotal: (j['sales_total'] as num?)?.toDouble() ?? 0,
        lastSale: j['last_sale'] == null ? null : DateTime.parse(j['last_sale'] as String),
        code: j['code'] as String?,
        claimed: (j['claimed'] as bool?) ?? true,
      );
}

/// Login + shop membership. All security is enforced in Supabase (row-level security),
/// this class only calls it.
class ShopService {
  SupabaseClient get _c => Supabase.instance.client;

  Session? get session => _c.auth.currentSession;
  String? get email => _c.auth.currentUser?.email;
  Stream<AuthState> get authChanges => _c.auth.onAuthStateChange;

  static const _authTimeout = Duration(seconds: 20);

  Future<void> signIn(String email, String password) => _c.auth
      .signInWithPassword(email: email, password: password)
      .timeout(_authTimeout);

  Future<AuthResponse> signUp(String email, String password) =>
      _c.auth.signUp(email: email, password: password).timeout(_authTimeout);

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

  /// The phone is signed out straight away; the server is told in the background,
  /// so a bad connection can no longer keep the person waiting.
  Future<void> signOut() async {
    try {
      await _c.auth.signOut().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// The shop the signed-in user belongs to, or null if they have not created/joined one yet.
  Future<ShopInfo?> myShop() async {
    final r = await _c.rpc('sm_my_shop');
    if (r == null) return null;
    final shop = ShopInfo.fromJson(Map<String, dynamic>.from(r as Map));
    // Remember the role so owner-only screens also work without internet.
    final uid = _c.auth.currentUser?.id;
    if (uid != null) {
      OfflineIdentity.setRole(uid, shop.role);
      _saveShopCache(uid, shop);
    }
    return shop;
  }

  static String _shopCacheKey(String uid) => 'sm_shop_cache_v1_$uid';

  /// Keeps the shop's name and the person's role on the phone (not the join code).
  Future<void> _saveShopCache(String uid, ShopInfo s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _shopCacheKey(uid),
        jsonEncode({'id': s.id, 'name': s.name, 'role': s.role, 'is_super_admin': s.isSuperAdmin}),
      );
    } catch (_) {}
  }

  /// The shop last saved on this phone, or null if there is none.
  Future<ShopInfo?> cachedShop() async {
    final uid = _c.auth.currentUser?.id ?? OfflineIdentity.userId;
    if (uid == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_shopCacheKey(uid));
      if (raw == null) return null;
      return ShopInfo.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  /// Like [myShop], but with no connection it returns the copy saved on this phone.
  Future<ShopLoad> myShopOrCached() async {
    try {
      final live = await myShop().timeout(const Duration(seconds: 12));
      return ShopLoad(live, false);
    } on PostgrestException {
      rethrow; // the server answered and refused: not a connection problem
    } catch (e) {
      final saved = await cachedShop();
      if (saved != null) return ShopLoad(saved, true);
      rethrow;
    }
  }

  /// Everyone in the owner's shop with their sales totals (owner only).
  Future<List<TeamMember>> team() async {
    final rows = await _c.rpc('sm_shop_team');
    return [
      for (final r in rows as List) TeamMember.fromJson(Map<String, dynamic>.from(r as Map))
    ];
  }

  /// Owner: adds a cashier by name and returns the cashier's login code.
  ///
  /// Safe on a weak connection: one request id is used for every try, and the
  /// server returns the same cashier if it already saved an earlier try (so a lost
  /// reply can never create a second cashier).
  Future<String> addCashier(String name) async {
    final requestId = const Uuid().v4();
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final r = await _c.rpc('sm_add_cashier', params: {
          'p_name': name,
          'p_request_id': requestId,
        }).timeout(const Duration(seconds: 20));
        return r as String;
      } on PostgrestException {
        rethrow; // the server answered and refused: trying again will not help
      } catch (e) {
        last = e; // no usable connection: wait a moment and try again
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
      }
    }
    throw last!;
  }

  /// Owner: gives a cashier a NEW code. The old code stops working at once and
  /// the cashier keeps their sales history. Safe on a weak connection: the same
  /// request id is used for every try, so a lost reply cannot make two codes.
  Future<String> resetCashierCode(String code) async {
    final requestId = const Uuid().v4();
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final r = await _c.rpc('sm_reset_cashier_code', params: {
          'p_code': normalizeCode(code),
          'p_request_id': requestId,
        }).timeout(const Duration(seconds: 20));
        return r as String;
      } on PostgrestException {
        rethrow;
      } catch (e) {
        last = e;
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
      }
    }
    throw last!;
  }

  /// Owner: removes a cashier who logs in with a code. The code stops working.
  Future<void> removeCashier(String code) =>
      _c.rpc('sm_remove_cashier', params: {'p_code': code});

  // ---------------------------------------------------------- cashier login
  /// Letters and digits only, upper case ("abcd-efgh" -> "ABCDEFGH").
  static String normalizeCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  // A cashier has no phone number or password. Behind the scenes the code is
  // used to make a private account the first time, and to sign in to it later,
  // so any phone can log in with the same code.
  static String _cashierEmail(String code) {
    // Same address domain the phone-number accounts already use.
    final sample = PhoneAuth.emailFor('0');
    final at = sample.indexOf('@');
    final domain = at >= 0 ? sample.substring(at) : '@smartmauzo.app';
    return 'cashier-${code.toLowerCase()}$domain';
  }

  static String _cashierPassword(String code) => 'Mauzo-$code';

  /// Signs in to the cashier's private account, making it the first time. Works
  /// whether or not Supabase has "Confirm email" switched on: a cashier account is
  /// confirmed by the database itself (sm_confirm_cashier_account).
  Future<void> _signInCashier(String code, String email, String password) async {
    Future<void> signIn() => _c.auth
        .signInWithPassword(email: email, password: password)
        .timeout(_authTimeout);
    Future<void> confirm() => _c
        .rpc('sm_confirm_cashier_account', params: {'p_code': code}).timeout(_authTimeout);

    try {
      await signIn();
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('not confirmed')) {
        await confirm();
        await signIn();
      } else if (m.contains('invalid login')) {
        // First time this code is used: make its account.
        final res = await _c.auth
            .signUp(email: email, password: password)
            .timeout(_authTimeout);
        if (res.session == null) {
          await confirm();
          await signIn();
        }
      } else {
        rethrow;
      }
    }
  }

  /// Log in with only the code the owner gave. Throws [FormatException] with a
  /// message that is safe to show.
  Future<void> cashierLogin(String rawCode) async {
    final code = normalizeCode(rawCode);
    if (code.length != 8) {
      throw const FormatException('Enter the 8-character code from your shop owner');
    }
    final ok = await _c
        .rpc('sm_cashier_code_ok', params: {'p_code': code}).timeout(_authTimeout);
    if (ok != true) {
      throw const FormatException('Code not recognised. Check it with your shop owner.');
    }

    final email = _cashierEmail(code);
    final password = _cashierPassword(code);
    // Show the join-only screen (never "Create shop") from the moment we sign in.
    SignupIntent.expectCashier();
    try {
      await _signInCashier(code, email, password);
      await _c
          .rpc('sm_claim_cashier_code', params: {'p_code': code}).timeout(_authTimeout);
      final uid = _c.auth.currentUser?.id;
      if (uid != null) await SignupIntent.markCashier(uid);
      shopChanged.value++;
    } catch (_) {
      SignupIntent.cancelPending();
      if (_c.auth.currentSession != null) await signOut();
      rethrow;
    }
  }

  /// Takes an older phone-number cashier out of the shop. Their past sales stay.
  Future<void> removeMember(String userId) =>
      _c.rpc('sm_remove_member', params: {'p_user_id': userId});

  /// Replaces the shop code; the old one stops working. Returns the new code.
  Future<String> newJoinCode() async {
    final r = await _c.rpc('sm_new_join_code');
    return r as String;
  }

  /// Goes up each time this user creates or joins a shop, so AuthGate can look
  /// again and open the app.
  static final ValueNotifier<int> shopChanged = ValueNotifier<int>(0);

  Future<void> createShop(String name) async {
    await _c.rpc('sm_create_shop', params: {'p_name': name});
    shopChanged.value++;
  }

  Future<void> joinShop(String code) async {
    await _c.rpc('sm_join_shop', params: {'p_code': code.trim().toUpperCase()});
    shopChanged.value++;
  }
}
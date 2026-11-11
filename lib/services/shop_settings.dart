import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business_type.dart';
import 'app_language.dart';
import 'offline_store.dart';

/// Settings of the signed-in user's shop, shared by owner and cashiers.
/// A copy is kept on the phone so the app adapts offline too. See shop_settings.sql.
class ShopSettings {
  /// null = not chosen yet (or not loaded yet).
  static final ValueNotifier<BusinessType?> type = ValueNotifier<BusinessType?>(null);

  /// True once the server has said this shop has no business type yet.
  static bool serverSaysUnset = false;

  static SupabaseClient get _c => Supabase.instance.client;
  static const _timeout = Duration(seconds: 12);
  static Future<void>? _inflight;

  static String? get _uid => _c.auth.currentUser?.id ?? OfflineIdentity.userId;
  static String _key(String uid) => 'sm_business_type_v1_$uid';

  /// Loads the saved copy first (instant, works offline), then asks the server.
  /// Calling it again while a load is running returns the same load.
  static Future<void> load() => _inflight ??= _load().whenComplete(() => _inflight = null);

  static Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      final saved = businessTypeFromKey(p.getString(_key(uid)));
      if (saved != null) type.value = saved;
    } catch (_) {}
    try {
      final r = await _c.rpc('sm_get_shop_settings').timeout(_timeout);
      final m = Map<String, dynamic>.from(r as Map);
      final t = businessTypeFromKey(m['business_type'] as String?);
      serverSaysUnset = t == null;
      if (t != null) {
        type.value = t;
        await _remember(uid, t);
      }
    } catch (_) {
      // Offline or the SQL is not installed yet: keep what the phone remembers.
    }
  }

  /// Owner only (the server refuses anyone else). Throws if it could not be saved.
  static Future<void> setBusinessType(BusinessType t) async {
    await _c.rpc('sm_set_business_type', params: {'p_type': t.name}).timeout(_timeout);
    serverSaysUnset = false;
    type.value = t;
    final uid = _uid;
    if (uid != null) await _remember(uid, t);
  }

  static Future<void> _remember(String uid, BusinessType t) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key(uid), t.name);
    } catch (_) {}
  }

  /// Forget everything (someone signed out).
  static void reset() {
    type.value = null;
    serverSaysUnset = false;
  }

  /// Product categories to suggest for this shop's business type, in the app language.
  static List<String> starterCategories() {
    final info = businessInfo(type.value ?? BusinessType.general);
    return AppLanguage.isSwahili ? info.categoriesSw : info.categoriesEn;
  }
}
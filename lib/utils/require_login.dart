import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/auth_screen.dart';
import '../services/offline_store.dart';

/// True if a user is currently logged in. A phone that was started without
/// internet may not have restored the login yet; it still counts as logged in
/// (remembered from the last time) until the user signs out.
bool get isLoggedIn =>
    Supabase.instance.client.auth.currentSession != null ||
    OfflineIdentity.isRemembered;

/// Call this before any action that needs an account (making a sale,
/// opening inventory, etc).
///
/// Returns true if the user is logged in. If they are a guest, it opens the
/// login/signup screen on top of the current screen and returns true only if
/// they successfully logged in.
///
/// Usage:
///   onTap: () async {
///     if (!await requireLogin(context)) return;
///     // ...do the protected thing
///   }
///
/// Pass [asCashier] to open the login page on the Cashier section (code only).
Future<bool> requireLogin(BuildContext context, {bool asCashier = false}) async {
  if (isLoggedIn) return true;

  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AuthScreen(startAsCashier: asCashier),
    ),
  );

  return isLoggedIn;
}
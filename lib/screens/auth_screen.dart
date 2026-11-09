import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/shop_service.dart';
import '../utils/phone_auth.dart';
import '../services/app_language.dart';
import '../widgets/language_switch.dart';

/// Login / sign-up screen. Opened on top of the app (via requireLogin) when a
/// guest tries to do something that needs an account.
class AuthScreen extends StatefulWidget {
  /// Open on the Cashier section (code only) instead of the Shop owner one.
  final bool startAsCashier;
  const AuthScreen({super.key, this.startAsCashier = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _svc = ShopService();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  late bool _isCashier = widget.startAsCashier; // false: owner (phone + password), true: cashier (code only)
  bool _isLogin = true;
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    _code.dispose();
    super.dispose();
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Close this screen (if it was opened as a prompt on top of the app).
  void _close() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  String? _validateNewPassword(String? v) {
    if (v == null || v.isEmpty) return tr('Please enter a password');
    if (v.length < 8) return 'Password must be at least 8 characters long';
    if (!v.contains(RegExp(r'[A-Z]'))) return 'Password must contain a capital letter';
    if (!v.contains(RegExp(r'[0-9]'))) return 'Password must contain a number';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final phone = _phone.text.trim();
      if (_isCashier) {
        // Cashier: the code is the only thing needed.
        await _svc.cashierLogin(_code.text);
        _close();
      } else if (_isLogin) {
        await _svc.signInWithPhone(phone, _password.text);
        // Logged in: AuthGate reacts to the new session. Close this prompt.
        _close();
      } else {
        final res = await _svc.signUpWithPhone(phone, _password.text);
        if (res.session == null) {
          // Supabase "Confirm email" is still switched on, so no session was created.
          _msg(tr('Account created. Please log in.'));
          if (mounted) setState(() => _isLogin = true);
        } else {
          // Signed up and logged in straight away.
          _close();
        }
      }
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login')) {
        _msg(friendly(e));
      } else if (m.contains('already registered') || m.contains('already been registered')) {
        _msg(friendly(e));
      } else {
        _msg(friendly(e));
      }
    } catch (e) {
      _msg(friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blue = Colors.blue[900]!;
    final canClose = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: Colors.white,
      // Close (X) button so guests can go back to browsing.
      appBar: canClose
          ? AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _busy ? null : _close,
              ),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: Alignment.centerRight, child: LanguageSwitch()),
                  const SizedBox(height: 8),
                  Image.asset(
                    'assets/images/logo.png',
                    height: 96,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.shopping_bag_rounded, size: 64, color: blue),
                  ),
                  const SizedBox(height: 12),
                  Text('Smart Mauzo',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold, color: blue)),
                  const SizedBox(height: 4),
                  Text(
                      _isCashier
                          ? tr('Cashier login')
                          : (_isLogin ? tr('Log in to your shop') : tr('Create your account')),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 24),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                          value: false, icon: Icon(Icons.storefront), label: Text(tr('Shop owner'))),
                      ButtonSegment(
                          value: true, icon: Icon(Icons.badge_outlined), label: Text(tr('Cashier'))),
                    ],
                    selected: {_isCashier},
                    showSelectedIcon: false,
                    onSelectionChanged: _busy
                        ? null
                        : (v) => setState(() {
                              _isCashier = v.first;
                              _formKey.currentState?.reset();
                            }),
                  ),
                  const SizedBox(height: 24),
                  if (_isCashier) ...[
                    TextFormField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 3),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        labelText: tr('Your cashier code'),
                        hintText: 'ABCD-EFGH',
                        helperText: tr('Your shop owner gives you this code.\nNo phone number or password needed.'),
                        helperMaxLines: 2,
                        prefixIcon: const Icon(Icons.vpn_key_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) => ShopService.normalizeCode(v ?? '').length == 8
                          ? null
                          : 'Enter the 8-character code',
                      onFieldSubmitted: (_) => _busy ? null : _submit(),
                    ),
                  ] else ...[
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: InputDecoration(
                      labelText: tr('Phone number'),
                      hintText: '0712 345 678',
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return tr('Please enter your phone number');
                      return PhoneAuth.normalize(v) == null
                          ? tr('Please enter a valid phone number')
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: tr('Password'),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: _isLogin
                        ? (v) => (v == null || v.isEmpty) ? tr('Please enter your password') : null
                        : _validateNewPassword,
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: tr('Confirm password'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) => v != _password.text ? tr('Passwords do not match') : null,
                    ),
                    const SizedBox(height: 8),
                    Text(tr('At least 8 characters, 1 capital letter and 1 number.'),
                        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_isCashier || _isLogin ? tr('Log in') : tr('Sign up'),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (!_isCashier)
                    TextButton(
                      onPressed: _busy ? null : () => setState(() => _isLogin = !_isLogin),
                      child: Text(_isLogin
                          ? tr('New here? Create an account')
                          : tr('Already have an account? Log in')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_language.dart';
import '../services/recovery_service.dart';
import '../services/shop_service.dart';
import '../utils/phone_auth.dart';
import '../widgets/language_switch.dart';

/// Forgotten password: phone number + the recovery code saved earlier + a new
/// password. Needs internet.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialPhone;
  const ForgotPasswordScreen({super.key, this.initialPhone = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone = TextEditingController(text: widget.initialPhone);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String? _validateNewPassword(String? v) {
    if (v == null || v.isEmpty) return tr('Please enter a password');
    if (v.length < 8) return 'Password must be at least 8 characters long';
    if (!v.contains(RegExp(r'[A-Z]'))) return 'Password must contain a capital letter';
    if (!v.contains(RegExp(r'[0-9]'))) return 'Password must contain a number';
    return null;
  }

  String _cleanCode() => _code.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = PhoneAuth.normalize(_phone.text);
    if (phone == null) return;
    setState(() => _busy = true);
    try {
      final r = await RecoveryService.resetPassword(
        phone: phone,
        code: _cleanCode(),
        newPassword: _password.text,
      );
      if (!mounted) return;
      switch (r) {
        case RecoveryResult.ok:
          try {
            await ShopService().signInWithPhone(phone, _password.text);
            _msg(tr('Password changed. You are now logged in.'));
            if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
          } catch (_) {
            _msg(tr('Password changed. Please log in.'));
            if (mounted) Navigator.of(context).pop();
          }
          return;
        case RecoveryResult.locked:
          _msg(tr('Too many wrong tries. Try again in 30 minutes.'));
          break;
        case RecoveryResult.weak:
          _msg('Password must be at least 8 characters long');
          break;
        case RecoveryResult.invalid:
          _msg(tr('Wrong phone number or recovery code.'));
          break;
      }
    } catch (_) {
      _msg(tr('Could not reset. Check your internet and try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blue = Colors.blue[900]!;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
      ),
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
                  Icon(Icons.lock_reset, size: 64, color: blue),
                  const SizedBox(height: 12),
                  Text(tr('Reset your password'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold, color: blue)),
                  const SizedBox(height: 6),
                  Text(
                    tr('Enter the recovery code you saved when you created your account.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
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
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]'))],
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: tr('Recovery code'),
                      hintText: 'XXXXX-XXXXX',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => _cleanCode().length == 10
                        ? null
                        : tr('Enter the 10-character recovery code'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: tr('New password'),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: _validateNewPassword,
                  ),
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
                          : Text(tr('Reset password'),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
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
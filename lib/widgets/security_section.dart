import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_language.dart';
import '../services/recovery_service.dart';
import 'recovery_code_dialog.dart';

/// Profile > Account security: recovery code status / new code, change password.
class SecuritySection extends StatefulWidget {
  const SecuritySection({super.key});

  @override
  State<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<SecuritySection> {
  bool? _hasCode; // null = still checking or could not check
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final v = await RecoveryService.hasCode();
      if (mounted) setState(() => _hasCode = v);
    } catch (_) {}
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _newCode() async {
    if (_hasCode == true) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('New recovery code')),
          content: Text(tr('The old recovery code stops working. Continue?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Continue'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final code = await RecoveryService.createCode();
      if (!mounted) return;
      setState(() => _hasCode = true);
      await showRecoveryCodeDialog(context, code);
    } catch (_) {
      _snack(tr('Could not create the code. Check your internet and try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (done == true) _snack(tr('Password changed'));
  }

  @override
  Widget build(BuildContext context) {
    final has = _hasCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.shield_outlined, color: Colors.blue[900]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Recovery code'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      has == null
                          ? '...'
                          : (has ? tr('Recovery code is set') : tr('No recovery code yet')),
                      style: TextStyle(
                          fontSize: 13,
                          color: has == false ? const Color(0xFFEF6C00) : Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _newCode,
                child: Text(has == true ? tr('New recovery code') : tr('Create')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _changePassword,
          icon: const Icon(Icons.lock_reset),
          label: Text(tr('Change password')),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validateNew(String? v) {
    if (v == null || v.isEmpty) return tr('Please enter a password');
    if (v.length < 8) return 'Password must be at least 8 characters long';
    if (!v.contains(RegExp(r'[A-Z]'))) return 'Password must contain a capital letter';
    if (!v.contains(RegExp(r'[0-9]'))) return 'Password must contain a number';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await RecoveryService.changePassword(current: _current.text, newPassword: _new.text);
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      setState(() => _error = m.contains('invalid login')
          ? tr('Current password is wrong')
          : e.message);
    } catch (_) {
      setState(() => _error = tr('Could not reset. Check your internet and try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Change password')),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _current,
                obscureText: true,
                decoration: InputDecoration(labelText: tr('Current password')),
                validator: (v) =>
                    (v == null || v.isEmpty) ? tr('Please enter your password') : null,
              ),
              TextFormField(
                controller: _new,
                obscureText: true,
                decoration: InputDecoration(labelText: tr('New password')),
                validator: _validateNew,
              ),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                decoration: InputDecoration(labelText: tr('Confirm password')),
                validator: (v) => v != _new.text ? tr('Passwords do not match') : null,
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(onPressed: _busy ? null : _save, child: Text(tr('Save'))),
      ],
    );
  }
}
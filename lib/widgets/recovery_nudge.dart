import 'package:flutter/material.dart';

import '../services/app_language.dart';
import '../services/recovery_service.dart';
import 'recovery_code_dialog.dart';

/// Wraps the logged-in app. Once per app start, if this phone-number account has
/// no recovery code yet, offers to create one. "Later" waits a few days.
class RecoveryNudge extends StatefulWidget {
  final Widget child;
  const RecoveryNudge({super.key, required this.child});

  @override
  State<RecoveryNudge> createState() => _RecoveryNudgeState();
}

class _RecoveryNudgeState extends State<RecoveryNudge> {
  static bool _askedThisRun = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  Future<void> _maybeAsk() async {
    if (_askedThisRun || !RecoveryService.isPhoneAccount) return;
    if (await RecoveryService.nudgeSnoozed()) return;
    bool has;
    try {
      has = await RecoveryService.hasCode();
    } catch (_) {
      return; // no internet: try again next time
    }
    if (has || !mounted) return;
    _askedThisRun = true;

    final create = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Protect your account')),
        content: Text(tr(
            'If you forget your password, a recovery code is the only way back into your shop. Create yours now and keep it safe.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Later'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Create recovery code'))),
        ],
      ),
    );
    if (!mounted) return;
    if (create != true) {
      await RecoveryService.snoozeNudge();
      return;
    }
    try {
      final code = await RecoveryService.createCode();
      if (!mounted) return;
      await showRecoveryCodeDialog(context, code);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Could not create the code. Check your internet and try again.'))));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
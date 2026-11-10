import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_language.dart';

/// Shows a freshly made recovery code once. It cannot be closed until the person
/// confirms they saved it.
Future<void> showRecoveryCodeDialog(BuildContext context, String code) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RecoveryCodeDialog(code: code),
  );
}

class _RecoveryCodeDialog extends StatefulWidget {
  final String code;
  const _RecoveryCodeDialog({required this.code});

  @override
  State<_RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<_RecoveryCodeDialog> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Your recovery code')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                widget.code,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                    color: Colors.blue[900]),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr('Write it down or take a screenshot and keep it safe. It is shown only once. Anyone with this code and your phone number can change your password, so never share it.'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.code));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(tr('Code copied'))));
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(tr('Copy')),
                ),
                TextButton.icon(
                  onPressed: () =>
                      Share.share('Smart Mauzo ${tr('Recovery code')}: ${widget.code}'),
                  icon: const Icon(Icons.share, size: 18),
                  label: Text(tr('Share...')),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _saved,
              onChanged: (v) => setState(() => _saved = v ?? false),
              title: Text(tr('I have saved my recovery code'),
                  style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _saved ? () => Navigator.pop(context) : null,
          child: Text(tr('Done')),
        ),
      ],
    );
  }
}
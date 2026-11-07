import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/offline_store.dart';
import '../services/sync_service.dart';
import '../utils/money.dart';

/// Shows sales that are saved on this phone but not on the server yet, and any
/// that the server refused. Hidden when there is nothing to report.
class PendingSyncBanner extends StatelessWidget {
  const PendingSyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = SyncService();
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final pending = sync.pendingCount;
        final failed = sync.failed;
        if (pending == 0 && failed.isEmpty) return const SizedBox.shrink();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pending > 0)
              _bar(
                color: Colors.orange,
                icon: Icons.cloud_upload_outlined,
                text: '$pending sale${pending == 1 ? '' : 's'} '
                    '(${tzs(sync.pendingTotal)}) waiting to sync',
                action: sync.syncing
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton(onPressed: sync.sync, child: const Text('Sync now')),
              ),
            if (failed.isNotEmpty)
              _bar(
                color: Colors.red,
                icon: Icons.error_outline,
                text: '${failed.length} sale${failed.length == 1 ? '' : 's'} '
                    'could not be saved',
                action: TextButton(
                  onPressed: () => _review(context, failed),
                  child: const Text('Review'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _bar({
    required MaterialColor color,
    required IconData icon,
    required String text,
    required Widget action,
  }) {
    return Container(
      width: double.infinity,
      color: color[50],
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: color[900])),
          ),
          action,
        ],
      ),
    );
  }

  void _review(BuildContext context, List<PendingSale> failed) {
    final sync = SyncService();
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Sales that could not be saved'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'The server refused these. Retry once the problem is fixed, or '
                'discard them to delete them from this phone.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              for (final s in failed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${DateFormat('d MMM, HH:mm').format(s.soldAt.toLocal())}'
                      '  •  ${tzs(s.total)}'),
                  subtitle: Text(s.error ?? 'Unknown error'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(d);
              sync.discardFailed();
            },
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(d);
              sync.retryFailed();
            },
            child: const Text('Retry'),
          ),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close')),
        ],
      ),
    );
  }
}
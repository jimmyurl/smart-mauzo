import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Shown above a screen that is displaying the copy saved on this phone because
/// there is no (usable) internet connection.
class OfflineDataBanner extends StatelessWidget {
  /// When the copy was saved (null if unknown).
  final DateTime? savedAt;
  const OfflineDataBanner({super.key, this.savedAt});

  @override
  Widget build(BuildContext context) {
    final when = savedAt == null
        ? ''
        : ' (updated ${DateFormat('d MMM, HH:mm').format(savedAt!.toLocal())})';
    return Container(
      width: double.infinity,
      color: Colors.orange[100],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 18, color: Colors.orange[900]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No internet. Showing the sales saved on this phone$when. '
              'Sales made offline appear here once they sync.',
              style: TextStyle(fontSize: 12, color: Colors.orange[900]),
            ),
          ),
        ],
      ),
    );
  }
}
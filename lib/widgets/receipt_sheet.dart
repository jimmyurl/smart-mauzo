import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/order.dart';
import '../services/receipt_service.dart';

/// Opens the receipt of [order]: a preview with Share (WhatsApp etc.), PDF and
/// Print buttons. [servedBy] is the seller's name (leave null to omit the line).
Future<void> showReceiptSheet(BuildContext context, Order order, {String? servedBy}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReceiptSheet(order: order, servedBy: servedBy),
  );
}

class _ReceiptSheet extends StatefulWidget {
  final Order order;
  final String? servedBy;
  const _ReceiptSheet({required this.order, this.servedBy});

  @override
  State<_ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<_ReceiptSheet> {
  String? _shopName;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ReceiptService.shopName().then((n) {
      if (mounted) setState(() => _shopName = n);
    });
  }

  String get _text => ReceiptService.buildText(widget.order,
      shopName: _shopName ?? '', servedBy: widget.servedBy);

  String get _fileName {
    final n = widget.order.orderNo;
    return n == null ? 'receipt.pdf' : 'receipt-$n.pdf';
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create the receipt: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareText() => _run(() async {
        final o = widget.order;
        await Share.share(_text,
            subject: o.number == null ? 'Receipt' : 'Receipt ${o.number}');
      });

  Future<void> _sharePdf() => _run(() async {
        final bytes = await ReceiptService.buildPdf(widget.order,
            shopName: _shopName ?? '', servedBy: widget.servedBy);
        await Printing.sharePdf(bytes: bytes, filename: _fileName);
      });

  Future<void> _print() => _run(() async {
        final order = widget.order;
        final shop = _shopName ?? '';
        final servedBy = widget.servedBy;
        await Printing.layoutPdf(
          name: _fileName,
          onLayout: (_) => ReceiptService.buildPdf(order, shopName: shop, servedBy: servedBy),
        );
      });

  @override
  Widget build(BuildContext context) {
    final ready = _shopName != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: ready
                      ? Text(_text.replaceAll('*', ''),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13))
                      : const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: ready && !_busy ? _shareText : null,
              icon: const Icon(Icons.share),
              label: const Text('Share (WhatsApp, SMS...)'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: ready && !_busy ? _sharePdf : null,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('PDF'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: ready && !_busy ? _print : null,
                    icon: const Icon(Icons.print),
                    label: const Text('Print'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

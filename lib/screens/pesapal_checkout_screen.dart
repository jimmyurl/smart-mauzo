import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/pesapal_service.dart';

/// Opens Pesapal's hosted page (M-Pesa, Tigo Pesa, Airtel Money, cards).
/// Pops with `true` only when Pesapal confirms the payment.
class PesapalCheckoutScreen extends StatefulWidget {
  final String productId;
  final int quantity;
  final double total;
  final String? customerPhone;
  const PesapalCheckoutScreen({
    super.key,
    required this.productId,
    required this.quantity,
    required this.total,
    this.customerPhone,
  });

  @override
  State<PesapalCheckoutScreen> createState() => _PesapalCheckoutScreenState();
}

class _PesapalCheckoutScreenState extends State<PesapalCheckoutScreen> {
  final _svc = PesapalService();
  WebViewController? _web;
  PesapalCheckout? _checkout;
  String? _error;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final c = await _svc.startPayment(
          productId: widget.productId,
          quantity: widget.quantity,
          phone: widget.customerPhone);
      _checkout = c;
      _web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (req) {
            if (req.url.startsWith('${c.returnBase}/return')) {
              _verify();
              return NavigationDecision.prevent;
            }
            if (req.url.startsWith('${c.returnBase}/cancel')) {
              Navigator.pop(context, false);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ))
        ..loadRequest(Uri.parse(c.payUrl));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _verify() async {
    if (_verifying) return;
    setState(() => _verifying = true);
    try {
      final r = await _svc.verify(_checkout!.transToken);
      if (!mounted) return;
      if (r.paid) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _verifying = false;
          _error = r.pending
              ? 'Payment not confirmed yet. If you approved it on your phone, wait a moment and tap Check again.'
              : 'Payment failed: ${r.message}';
        });
      }
    } catch (e) {
      if (mounted) setState(() { _verifying = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pay TZS ${widget.total.toStringAsFixed(0)}')),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                if (_checkout != null)
                  ElevatedButton(
                    onPressed: () { setState(() => _error = null); _verify(); },
                    child: const Text('Check again'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ]),
            )
          : (_web == null || _verifying)
              ? const Center(child: CircularProgressIndicator())
              : WebViewWidget(controller: _web!),
    );
  }
}
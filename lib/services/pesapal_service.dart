import 'package:supabase_flutter/supabase_flutter.dart';

class PesapalCheckout {
  final String payUrl;
  final String transToken;
  final String returnBase;
  PesapalCheckout(this.payUrl, this.transToken, this.returnBase);
}

class PaymentResult {
  final bool paid;
  final bool pending;
  final String message;
  PaymentResult(this.paid, this.pending, this.message);
}

/// Talks only to your own Supabase Edge Functions. No Pesapal secrets live in the app.
class PesapalService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<Map<String, dynamic>> _call(String fn, Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(fn, body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final d = e.details;
      throw (d is Map && d['error'] != null)
          ? '${d['error']}'
          : 'Payment service error (${e.status})';
    }
  }

  /// Starts a Pesapal payment for a whole cart.
  /// Each item must contain 'product_id' and 'quantity'. Any 'unit_price' is
  /// deliberately NOT sent: the server must price the order from the database.
  Future<PesapalCheckout> startPayment({
    required List<Map<String, dynamic>> items,
    String? phone,
  }) async {
    final d = await _call('pesapal-create', {
      'items': [
        for (final i in items)
          {'product_id': i['product_id'], 'quantity': i['quantity']}
      ],
      if (phone != null) 'phone': phone,
    });
    return PesapalCheckout(d['pay_url'], d['trans_token'], d['return_base']);
  }

  Future<PaymentResult> verify(String transToken) async {
    final d = await _call('pesapal-verify', {'trans_token': transToken});
    return PaymentResult(d['paid'] == true, d['pending'] == true, '${d['message'] ?? ''}');
  }
}
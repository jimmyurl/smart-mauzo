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
      throw (d is Map && d['error'] != null) ? '${d['error']}' : 'Payment service error (${e.status})';
    }
  }

  Future<PesapalCheckout> startPayment({
    required String productId,
    required int quantity,
    String? phone,
  }) async {
    final d = await _call('pesapal-create',
        {'product_id': productId, 'quantity': quantity, if (phone != null) 'phone': phone});
    return PesapalCheckout(d['pay_url'], d['trans_token'], d['return_base']);
  }

  Future<PaymentResult> verify(String transToken) async {
    final d = await _call('pesapal-verify', {'trans_token': transToken});
    return PaymentResult(d['paid'] == true, d['pending'] == true, '${d['message'] ?? ''}');
  }
}
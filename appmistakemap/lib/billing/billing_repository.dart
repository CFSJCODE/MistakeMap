import 'package:supabase_flutter/supabase_flutter.dart';

import 'checkout_models.dart';

typedef BillingData = Map<String, dynamic>;

BillingData billingMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<BillingData> billingRows(Object? v) =>
    v is List ? [for (final item in v) billingMap(item)] : <BillingData>[];

/// Cobrança da escola. Toda leitura e escrita passa pela Edge Function
/// school-billing, que confere quem paga no banco e fala com o Asaas. O app
/// nunca vê a chave do Asaas nem guarda dados de cartão.
abstract interface class BillingRepository {
  Future<BillingData> run(String action, [BillingData data = const {}]);
}

class SupabaseBillingRepository implements BillingRepository {
  SupabaseBillingRepository(this.client);
  final SupabaseClient client;

  @override
  Future<BillingData> run(String action, [BillingData data = const {}]) async {
    try {
      final response = await client.functions
          .invoke('school-billing', body: {...data, 'action': action})
          .timeout(const Duration(seconds: 45));
      final body = billingMap(response.data);
      if (response.status >= 400 || body.containsKey('error')) {
        throw CheckoutFailure(
          body['message'] as String? ?? 'Não foi possível concluir agora.',
        );
      }
      return body;
    } on FunctionException catch (error) {
      throw CheckoutFailure(
        billingMap(error.details)['message'] as String? ??
            'Não foi possível falar com o servidor. Confira a conexão.',
      );
    } on CheckoutFailure {
      rethrow;
    } catch (_) {
      throw const CheckoutFailure(
        'Não foi possível falar com o servidor. Confira a conexão.',
      );
    }
  }
}

/// Checkout de verdade: a cobrança é criada no Asaas pela Edge Function e o
/// pagamento só conta depois que o Asaas confirma (webhook ou consulta).
class ServerCheckoutGateway implements CheckoutGateway {
  ServerCheckoutGateway({required this.repository, required this.schoolId});

  final BillingRepository repository;
  final String schoolId;

  @override
  CheckoutQuote quote({
    required CheckoutPlan plan,
    required int students,
    required CheckoutCycle cycle,
    required CheckoutMethod method,
  }) => CheckoutQuote.estimate(
    plan: plan,
    students: students,
    cycle: cycle,
    method: method,
  );

  @override
  Future<CheckoutCharge> createCharge(
    CheckoutQuote quote, {
    CheckoutCard? card,
  }) async {
    if (quote.plan.isFree) {
      throw const CheckoutFailure('O plano Grátis não gera cobrança.');
    }
    final body = await repository.run('checkout', {
      'school_id': schoolId,
      'plan': quote.plan.id,
      'cycle': quote.cycle.wire,
      'students': quote.students,
      'method': quote.method.wire,
      if (quote.method == CheckoutMethod.creditCard && card != null)
        'card': card.toJson(),
      if (quote.method == CheckoutMethod.creditCard && card == null)
        'use_saved_card': true,
    });
    return chargeFromInvoice(billingMap(body['invoice']), quote);
  }

  @override
  Future<CheckoutReceipt?> check(CheckoutCharge charge) async {
    final body = await repository.run('invoice_status', {
      'invoice_id': charge.invoiceId,
    });
    final invoice = billingMap(body['invoice']);
    switch (invoice['status']) {
      case 'paid':
        return receiptFromInvoice(invoice, charge.quote);
      case 'canceled':
      case 'failed':
        throw CheckoutFailure(
          invoice['failure_reason'] as String? ??
              'Esta cobrança foi cancelada. Gere uma nova.',
        );
      default:
        return null;
    }
  }
}

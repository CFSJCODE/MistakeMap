import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../theme/motion.dart';
import '../auth/team_login.dart';
import '../school/escola_ui.dart';
import '../theme/design_tokens.dart';
import 'billing_repository.dart';
import 'checkout_models.dart';
import 'checkout_page.dart';

/// Cobrança no painel da escola (dono, Financeiro/Compras e coordenação).
///
/// - Dono: escolhe quem paga (ele ou o Financeiro) e sempre acompanha as
///   faturas.
/// - Quem paga: escolhe o plano, paga (Pix, boleto ou cartão) e mantém os
///   dados de cobrança (CNPJ, pedido de compra, centro de custo…).
/// - Coordenação: só vê quem paga, para saber a quem pedir.
///
/// O servidor confere tudo de novo; aqui só se decide o que mostrar.
class CartaoCobranca extends StatefulWidget {
  const CartaoCobranca({
    super.key,
    required this.escolaId,
    required this.escolaNome,
    required this.papel,
    required this.repositorio,
    this.mostrarCobrancaTeste = kTeamBuild,
  });

  final String escolaId;
  final String escolaNome;
  final String papel;
  final BillingRepository repositorio;

  /// Botão "Cobrança de teste (R$ 5)": só no app da equipe, para que um
  /// cliente não gere um Pix de teste por engano no app de produção.
  final bool mostrarCobrancaTeste;

  @override
  State<CartaoCobranca> createState() => _CartaoCobrancaState();
}

const _status = {
  'pending': 'Pendente',
  'awaiting_payment': 'Aguardando pagamento',
  'paid': 'Paga',
  'overdue': 'Vencida',
  'canceled': 'Cancelada',
  'failed': 'Recusada',
};

const _nfse = {
  'scheduled': 'NFS-e agendada',
  'issued': 'NFS-e emitida',
  'error': 'NFS-e com erro',
  'canceled': 'NFS-e cancelada',
  'not_configured': 'NFS-e pendente de configuração',
};

class _CartaoCobrancaState extends State<CartaoCobranca> {
  BillingData _dados = {};
  bool _carregando = true;
  bool _salvando = false;
  String? _erro;
  String? _aviso;
  bool _editando = false;

  String _pagante = 'owner';
  String _forma = 'pix';
  final _cnpj = TextEditingController();
  final _razao = TextEditingController();
  final _email = TextEditingController();
  final _pedido = TextEditingController();
  final _centro = TextEditingController();
  final _cep = TextEditingController();
  final _numero = TextEditingController();
  final _telefone = TextEditingController();
  final _prazo = TextEditingController();

  List<TextEditingController> get _campos => [
    _cnpj,
    _razao,
    _email,
    _pedido,
    _centro,
    _cep,
    _numero,
    _telefone,
    _prazo,
  ];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in _campos) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final dados = await widget.repositorio.run('overview', {
        'school_id': widget.escolaId,
      });
      if (!mounted) return;
      final s = billingMap(dados['settings']);
      final escola = billingMap(dados['school']);
      _pagante = '${s['payer_role'] ?? 'owner'}';
      _forma = '${s['default_method'] ?? 'pix'}';
      _cnpj.text = '${escola['cnpj'] ?? ''}';
      _razao.text = '${s['legal_name'] ?? ''}';
      _email.text = '${s['billing_email'] ?? ''}';
      _pedido.text = '${s['purchase_order'] ?? ''}';
      _centro.text = '${s['cost_center'] ?? ''}';
      _cep.text = '${s['postal_code'] ?? ''}';
      _numero.text = '${s['address_number'] ?? ''}';
      _telefone.text = '${s['phone'] ?? ''}';
      _prazo.text = '${s['due_days'] ?? 5}';
      setState(() => _dados = dados);
    } on CheckoutFailure catch (f) {
      if (mounted) setState(() => _erro = f.message);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    setState(() {
      _salvando = true;
      _erro = null;
      _aviso = null;
    });
    final dono = _papeis.contains('owner');
    try {
      await widget.repositorio.run('save_settings', {
        'school_id': widget.escolaId,
        if (dono) 'payer_role': _pagante,
        'default_method': _forma,
        'due_days': int.tryParse(_prazo.text.trim()) ?? 5,
        if (_cnpj.text.trim().isNotEmpty) 'cnpj': _cnpj.text.trim(),
        'legal_name': _razao.text.trim(),
        'billing_email': _email.text.trim(),
        'purchase_order': _pedido.text.trim(),
        'cost_center': _centro.text.trim(),
        'postal_code': _cep.text.trim(),
        'address_number': _numero.text.trim(),
        'phone': _telefone.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _editando = false;
        _aviso = 'Dados de cobrança salvos.';
      });
      await _carregar();
    } on CheckoutFailure catch (f) {
      if (mounted) setState(() => _erro = f.message);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _pagar() async {
    final s = billingMap(_dados['settings']);
    final quota = billingMap(_dados['quota']);
    final ativos = quota['active_students'] is int
        ? quota['active_students'] as int
        : 30;
    await Navigator.of(context).push(
      MistakeMapPageRoute(
        context: context,
        builder: (_) => SchoolCheckoutPage(
          schoolName: widget.escolaNome,
          gateway: ServerCheckoutGateway(
            repository: widget.repositorio,
            schoolId: widget.escolaId,
          ),
          savedCardLast4: s['card_last4'] as String?,
          initialStudents: ativos < 5 ? 30 : ativos,
          currentPlanId: billingMap(_dados['school'])['plan'] as String?,
        ),
      ),
    );
    if (mounted) await _carregar();
  }

  /// Cobrança de teste de R\$ 5 (Pix) numa escola real: prova o Asaas e o
  /// webhook sem contratar plano. Paga, não muda o plano nem gera nota.
  Future<void> _cobrancaTeste() async {
    if (_salvando) return;
    setState(() {
      _salvando = true;
      _erro = null;
      _aviso = null;
    });
    try {
      await widget.repositorio.run('test_charge', {
        'school_id': widget.escolaId,
        'method': 'pix',
      });
      if (!mounted) return;
      setState(
        () => _aviso =
            'Cobrança de teste de R\$ 5 gerada. Copie o Pix na fatura abaixo, '
            'pague e toque em Atualizar: ela deve aparecer como Paga.',
      );
      await _carregar();
    } on CheckoutFailure catch (f) {
      if (mounted) setState(() => _erro = f.message);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _reemitir(BillingData fatura, {String? forma}) async {
    setState(() => _erro = null);
    try {
      await widget.repositorio.run('issue_invoice', {
        'invoice_id': fatura['id'],
        'method': ?forma,
      });
      if (mounted) await _carregar();
    } on CheckoutFailure catch (f) {
      if (mounted) setState(() => _erro = f.message);
    }
  }

  List<String> get _papeis => [
    for (final r in (_dados['my_roles'] as List?) ?? const []) '$r',
  ];

  @override
  Widget build(BuildContext context) {
    if (_carregando && _dados.isEmpty) {
      return const CartaoEscola(
        titulo: 'Plano e cobrança',
        children: [Center(child: ProgressRing())],
      );
    }
    final escola = billingMap(_dados['school']);
    final s = billingMap(_dados['settings']);
    final faturas = billingRows(_dados['invoices']);
    final previsao = billingMap(_dados['forecast']);
    final quota = billingMap(_dados['quota']);
    final paga = _dados['is_payer'] == true;
    final dono = _papeis.contains('owner');
    final pagante = '${s['payer_role'] ?? 'owner'}';
    final ativo = _dados['provider'] == 'asaas';
    final verValores = dono || _papeis.contains('finance');
    final demo = s['demo'] == true;
    return CartaoEscola(
      titulo: 'Plano e cobrança',
      subtitulo:
          'Plano ${checkoutPlan('${escola['plan'] ?? 'free'}').name} · '
          'quem paga: ${pagante == 'finance' ? 'Financeiro/Compras' : 'dono da escola'}',
      children: [
        if (_erro != null) AvisoEscola(_erro!),
        if (_aviso != null) AvisoEscola(_aviso!, sucesso: true),
        if (!ativo && verValores)
          const AvisoEscola(
            'O pagamento pelo Asaas ainda está sendo ativado no servidor. '
            'Os dados de cobrança já podem ser preenchidos.',
          ),
        if (!verValores)
          Text(
            pagante == 'finance'
                ? 'Plano e pagamento ficam com o Financeiro/Compras da escola.'
                : 'Plano e pagamento ficam com o dono da escola.',
            style: const TextStyle(color: MistakeMapDesign.content),
          ),
        if (verValores) ...[
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _Numero(
                'Alunos ativos no mês',
                formatThousands(
                  quota['active_students'] is int
                      ? quota['active_students'] as int
                      : 0,
                ),
              ),
              if (previsao['total'] is num)
                _Numero(
                  'Previsão da fatura',
                  formatBrl((previsao['total'] as num).toDouble()),
                ),
              if ((previsao['volume_discount_percent'] ?? 0) is int &&
                  (previsao['volume_discount_percent'] ?? 0) as int > 0)
                _Numero(
                  'Desconto por volume',
                  '−${previsao['volume_discount_percent']}%',
                ),
              if (s['card_last4'] != null)
                _Numero('Cartão salvo', '•••• ${s['card_last4']}'),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (paga)
                BotaoEscola(
                  'Escolher plano e pagar',
                  principal: true,
                  onPressed: ativo ? _pagar : null,
                ),
              BotaoEscola(
                _editando ? 'Fechar dados de cobrança' : 'Dados de cobrança',
                onPressed: () => setState(() => _editando = !_editando),
              ),
              if (paga && !demo && widget.mostrarCobrancaTeste)
                BotaoEscola(
                  r'Cobrança de teste (R$ 5)',
                  onPressed: ativo && !_salvando ? _cobrancaTeste : null,
                ),
              if (faturas.isNotEmpty)
                BotaoEscola(
                  'Atualizar',
                  onPressed: _carregando ? null : _carregar,
                ),
            ],
          ),
          if (paga && !demo && widget.mostrarCobrancaTeste)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                r'A cobrança de teste gera um Pix real de R$ 5 para conferir '
                'o pagamento de ponta a ponta. Não muda o plano e não emite '
                'nota fiscal.',
                style: TextStyle(color: MistakeMapDesign.steel),
              ),
            ),
          if (!paga)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Nesta escola quem escolhe o plano e paga é o '
                'Financeiro/Compras. Você acompanha as faturas aqui.',
                style: TextStyle(color: MistakeMapDesign.steel),
              ),
            ),
          if (_editando) ...[
            const SizedBox(height: 16),
            if (dono)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: InfoLabel(
                  label: 'Quem paga',
                  child: ComboBox<String>(
                    value: _pagante,
                    items: const [
                      ComboBoxItem(
                        value: 'owner',
                        child: Text('Dono da escola (escola pequena)'),
                      ),
                      ComboBoxItem(
                        value: 'finance',
                        child: Text('Financeiro/Compras (rede)'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _pagante = v ?? 'owner'),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InfoLabel(
                label: 'Forma de pagamento das faturas mensais',
                child: ComboBox<String>(
                  value: _forma,
                  items: const [
                    ComboBoxItem(value: 'pix', child: Text('Pix')),
                    ComboBoxItem(value: 'boleto', child: Text('Boleto')),
                    ComboBoxItem(
                      value: 'credit_card',
                      child: Text('Cartão salvo'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _forma = v ?? 'pix'),
                ),
              ),
            ),
            CampoEscola(
              rotulo: 'CNPJ (obrigatório para cobrar)',
              controle: _cnpj,
              dica: '00.000.000/0000-00',
              teclado: TextInputType.number,
              formatos: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9./-]')),
              ],
            ),
            CampoEscola(rotulo: 'Razão social', controle: _razao),
            CampoEscola(
              rotulo: 'E-mail de cobrança (recebe boleto e nota)',
              controle: _email,
              teclado: TextInputType.emailAddress,
            ),
            CampoEscola(rotulo: 'Pedido de compra', controle: _pedido),
            CampoEscola(rotulo: 'Centro de custo', controle: _centro),
            CampoEscola(
              rotulo: 'Prazo do boleto/Pix (dias)',
              controle: _prazo,
              teclado: TextInputType.number,
              formatos: [FilteringTextInputFormatter.digitsOnly],
            ),
            const Text(
              'Para pagar com cartão, o Asaas pede também o endereço e o '
              'telefone do titular:',
              style: TextStyle(color: MistakeMapDesign.steel),
            ),
            const SizedBox(height: 8),
            CampoEscola(
              rotulo: 'CEP',
              controle: _cep,
              teclado: TextInputType.number,
              formatos: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
            ),
            CampoEscola(rotulo: 'Número do endereço', controle: _numero),
            CampoEscola(
              rotulo: 'Telefone',
              controle: _telefone,
              teclado: TextInputType.phone,
            ),
            BotaoEscola(
              _salvando ? 'Salvando…' : 'Salvar dados de cobrança',
              principal: true,
              onPressed: _salvando ? null : _salvar,
            ),
          ],
          if (faturas.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Faturas',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 8),
            for (final f in faturas.take(12))
              _LinhaFatura(
                fatura: f,
                podePagar: paga,
                onReemitir: (forma) => _reemitir(f, forma: forma),
              ),
          ],
        ],
      ],
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero(this.rotulo, this.valor);

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        rotulo,
        style: const TextStyle(fontSize: 12, color: MistakeMapDesign.steel),
      ),
      Text(
        valor,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: MistakeMapDesign.abyss,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

class _LinhaFatura extends StatelessWidget {
  const _LinhaFatura({
    required this.fatura,
    required this.podePagar,
    required this.onReemitir,
  });

  final BillingData fatura;
  final bool podePagar;
  final void Function(String? forma) onReemitir;

  @override
  Widget build(BuildContext context) {
    final status = '${fatura['status']}';
    final metodo = CheckoutMethod.fromWire(fatura['method']);
    final mes = DateTime.tryParse('${fatura['reference_month']}');
    final total = fatura['total'] is num
        ? formatBrl((fatura['total'] as num).toDouble())
        : '—';
    final codigo = metodo == CheckoutMethod.pix
        ? fatura['pix_payload']
        : fatura['boleto_line'];
    final cor = switch (status) {
      'paid' => MistakeMapDesign.mintInk,
      'overdue' || 'failed' => MistakeMapDesign.coralInk,
      'awaiting_payment' || 'pending' => MistakeMapDesign.amberInk,
      _ => MistakeMapDesign.steel,
    };
    final titulo = switch (fatura['kind']) {
      'checkout' => 'Contratação ${checkoutPlan('${fatura['plan']}').name}',
      'test' => 'Cobrança de teste',
      _ =>
        'Fechamento ${mes == null ? '' : '${mes.month.toString().padLeft(2, '0')}/${mes.year}'}',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MistakeMapDesign.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MistakeMapDesign.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                total,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Text(
            [
              _status[status] ?? status,
              metodo.label,
              if (fatura['card_last4'] != null) 'final ${fatura['card_last4']}',
              if (fatura['purchase_order'] != null)
                'PC ${fatura['purchase_order']}',
              if (_nfse[fatura['nfse_status']] != null)
                _nfse[fatura['nfse_status']]!,
              if (fatura['nfse_number'] != null) 'nº ${fatura['nfse_number']}',
            ].join(' · '),
            style: TextStyle(fontSize: 12.5, color: cor),
          ),
          if (fatura['failure_reason'] != null && status != 'paid')
            Text(
              '${fatura['failure_reason']}',
              style: const TextStyle(
                fontSize: 12,
                color: MistakeMapDesign.steel,
              ),
            ),
          if (podePagar) ...[
            if ((status == 'awaiting_payment' || status == 'overdue') &&
                codigo is String &&
                codigo.isNotEmpty)
              HyperlinkButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: codigo)),
                child: Text(
                  metodo == CheckoutMethod.pix
                      ? 'Copiar Pix copia e cola'
                      : 'Copiar linha digitável',
                ),
              ),
            if (status == 'failed' || status == 'pending')
              Wrap(
                spacing: 8,
                children: [
                  HyperlinkButton(
                    onPressed: () => onReemitir('pix'),
                    child: const Text('Gerar de novo em Pix'),
                  ),
                  HyperlinkButton(
                    onPressed: () => onReemitir('boleto'),
                    child: const Text('Gerar em boleto'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

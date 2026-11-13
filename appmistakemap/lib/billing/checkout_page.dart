import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';

import '../theme/design_tokens.dart';
import '../theme/glass_surface.dart';
import 'checkout_models.dart';

/// Assinatura da escola, do plano ao recibo (protótipo "Checkout
/// MistakeMap"): escolha do plano em carrossel 3D, confirmação, Pix, boleto
/// ou cartão, plano ativado e recibo impresso com o carimbo de pago.
///
/// A cobrança é real: [CheckoutGateway] cria a cobrança no Asaas pela Edge
/// Function e a tela só mostra "pago" depois que o Asaas confirma.
class SchoolCheckoutPage extends StatefulWidget {
  const SchoolCheckoutPage({
    super.key,
    required this.schoolName,
    required this.gateway,
    this.savedCardLast4,
    this.initialStudents = 30,
    this.currentPlanId,
    this.pollEvery = const Duration(seconds: 5),
  });

  final String schoolName;
  final CheckoutGateway gateway;

  /// Final do cartão já salvo no Asaas (só o token fica no servidor).
  final String? savedCardLast4;
  final int initialStudents;

  /// Plano que a escola já tem: o carrossel abre nele e o marca como atual.
  final String? currentPlanId;

  /// Intervalo da consulta enquanto o Pix ou o boleto aguardam pagamento.
  final Duration pollEvery;

  @override
  State<SchoolCheckoutPage> createState() => _SchoolCheckoutPageState();
}

class _SchoolCheckoutPageState extends State<SchoolCheckoutPage> {
  CheckoutGateway get _gateway => widget.gateway;

  int _step = 0;
  bool _forward = true;
  late int _planIndex = _initialPlanIndex(widget.currentPlanId);

  static int _initialPlanIndex(String? id) {
    final i = checkoutPlans.indexWhere((p) => p.id == id);
    // Quem está no Grátis (ou sem plano) vê primeiro o plano pago de entrada.
    return i <= 0 ? 1 : i;
  }

  late int _students = widget.initialStudents.clamp(5, maxCheckoutStudents);
  CheckoutCycle _cycle = CheckoutCycle.annual;
  CheckoutMethod _method = CheckoutMethod.pix;
  late bool _useSavedCard = widget.savedCardLast4 != null;
  bool _busy = false;
  bool _paid = false;
  bool _checking = false;
  CheckoutCharge? _charge;
  CheckoutReceipt? _receipt;
  String? _error;
  Timer? _poll;

  final _cardName = TextEditingController();
  final _cardNumber = TextEditingController();
  final _cardExpiry = TextEditingController();
  final _cardCcv = TextEditingController();

  CheckoutPlan get _plan => checkoutPlans[_planIndex];

  CheckoutQuote get _quote => _gateway.quote(
    plan: _plan,
    students: _students,
    cycle: _cycle,
    method: _method,
  );

  @override
  void dispose() {
    _poll?.cancel();
    for (final c in [_cardName, _cardNumber, _cardExpiry, _cardCcv]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(int step) => setState(() {
    _forward = step > _step;
    _step = step;
    _error = null;
    if (step != 2) _poll?.cancel();
  });

  void _back() {
    if (_step == 0) {
      Navigator.maybePop(context);
      return;
    }
    // Do recibo volta para o plano ativado; da cobrança, para a confirmação.
    _go(_step - 1);
  }

  CheckoutCard _typedCard() {
    final expiry = _cardExpiry.text.replaceAll(RegExp(r'[^0-9]'), '');
    return CheckoutCard(
      holderName: _cardName.text,
      number: _cardNumber.text,
      expiryMonth: expiry.length >= 2 ? expiry.substring(0, 2) : expiry,
      expiryYear: expiry.length > 2 ? expiry.substring(2) : '',
      ccv: _cardCcv.text,
    );
  }

  /// Número e código do cartão não ficam na tela depois da tentativa.
  void _forgetCard() {
    _cardNumber.clear();
    _cardCcv.clear();
  }

  Future<void> _generate() async {
    if (_plan.isFree) {
      Navigator.maybePop(context);
      return;
    }
    CheckoutCard? card;
    if (_method == CheckoutMethod.creditCard && !_useSavedCard) {
      card = _typedCard();
      final problem = card.problem(DateTime.now());
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final charge = await _gateway.createCharge(_quote, card: card);
      if (!mounted) return;
      _charge = charge;
      _paid = false;
      if (charge.paid) {
        final receipt = await _gateway.check(charge);
        if (!mounted) return;
        if (receipt != null) {
          _receipt = receipt;
          _go(3);
          return;
        }
      }
      _go(2);
      _poll?.cancel();
      _poll = Timer.periodic(widget.pollEvery, (_) => _check());
    } on CheckoutFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não deu para gerar a cobrança agora.');
      }
    } finally {
      if (card != null) _forgetCard();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Consulta o Asaas pelo servidor. Só mostra "pago" com a confirmação.
  Future<void> _check({bool manual = false}) async {
    final charge = _charge;
    if (charge == null || _paid || _checking) return;
    _checking = true;
    try {
      final receipt = await _gateway.check(charge);
      if (!mounted) return;
      if (receipt == null) {
        if (manual) {
          setState(
            () => _error =
                'O Asaas ainda não recebeu o pagamento. Pix costuma cair em '
                'segundos; boleto, em até 1 dia útil.',
          );
        }
        return;
      }
      _poll?.cancel();
      _receipt = receipt;
      setState(() {
        _paid = true;
        _error = null;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      if (mounted && _step == 2) _go(3);
    } on CheckoutFailure catch (failure) {
      _poll?.cancel();
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      // Sem rede agora: a próxima consulta tenta de novo.
      if (manual && mounted) {
        setState(() => _error = 'Sem conexão para conferir agora.');
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: NavigationView(
        content: AuroraBackground(
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AnimatedSwitcher(
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 450),
                  switchInCurve: const Cubic(.2, .8, .2, 1),
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) {
                    final entering =
                        child.key == ValueKey('checkout-step-$_step');
                    final dx = (entering == _forward ? 1 : -1) * 40.0;
                    return FadeTransition(
                      opacity: animation,
                      child: AnimatedBuilder(
                        animation: animation,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(dx * (1 - animation.value), 0),
                          child: child,
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey('checkout-step-$_step'),
                    child: _screen(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _screen() => switch (_step) {
    0 => _PlanStep(
      schoolName: widget.schoolName,
      index: _planIndex,
      currentPlanId: widget.currentPlanId,
      onIndex: (i) => setState(() => _planIndex = i),
      onBack: _back,
      onChoose: () => _go(1),
    ),
    1 => _ConfirmStep(
      quote: _quote,
      busy: _busy,
      error: _error,
      onBack: _back,
      onStudents: (n) => setState(() => _students = n),
      onCycle: (c) => setState(() => _cycle = c),
      onMethod: (m) => setState(() {
        _method = m;
        _error = null;
      }),
      savedCardLast4: widget.savedCardLast4,
      useSavedCard: _useSavedCard,
      onUseSavedCard: (v) => setState(() => _useSavedCard = v),
      cardName: _cardName,
      cardNumber: _cardNumber,
      cardExpiry: _cardExpiry,
      cardCcv: _cardCcv,
      onPay: _generate,
    ),
    2 => _ChargeStep(
      charge: _charge!,
      paid: _paid,
      error: _error,
      onBack: _back,
      onCheck: () => _check(manual: true),
    ),
    3 => _ActivatedStep(
      receipt: _receipt!,
      onReceipt: () => _go(4),
      onDone: () => Navigator.maybePop(context),
    ),
    _ => _ReceiptStep(
      receipt: _receipt!,
      schoolName: widget.schoolName,
      onBack: _back,
      onDone: () => Navigator.maybePop(context),
    ),
  };
}

// ─── Estilos ────────────────────────────────────────────────────────────────

const _display = TextStyle(
  color: MistakeMapDesign.abyss,
  fontSize: 26,
  height: 1.1,
  fontWeight: FontWeight.w700,
  letterSpacing: -.3,
);
const _sub = TextStyle(color: MistakeMapDesign.steel, height: 1.45);
const _eyebrow = TextStyle(
  fontSize: 11,
  letterSpacing: .9,
  fontWeight: FontWeight.w600,
  color: MistakeMapDesign.steel,
);
const _mono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Consolas', 'Menlo', 'Roboto Mono', 'Courier New'],
  fontSize: 10.5,
  height: 1.7,
  color: MistakeMapDesign.deep,
);
const _cardShadow = [
  BoxShadow(
    color: Color(0x5911212D),
    blurRadius: 40,
    spreadRadius: -18,
    offset: Offset(0, 18),
  ),
  BoxShadow(color: Color(0x0F11212D), blurRadius: 6, offset: Offset(0, 2)),
];

Duration _d(BuildContext context, int ms) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: ms);

/// Visual de cada plano: gradiente do cartão e cor da tinta.
({LinearGradient fill, Color ink, bool bordered}) _planLook(String id) =>
    switch (id) {
      'escola' => (
        fill: const LinearGradient(
          begin: Alignment(-.6, -1),
          end: Alignment(.6, 1),
          colors: [Color(0xFF8FF0E4), MistakeMapDesign.aqua, Color(0xFF5FB6FF)],
          stops: [0, .38, 1],
        ),
        ink: MistakeMapDesign.abyss,
        bordered: false,
      ),
      'plus' => (
        // Violeta um tom mais fundo que o protótipo: texto branco ≥ 4,5:1.
        fill: const LinearGradient(
          begin: Alignment(-.6, -1),
          end: Alignment(.6, 1),
          colors: [Color(0xFFC4B5FF), Color(0xFF7E5BF2), Color(0xFF5468E8)],
          stops: [0, .45, 1],
        ),
        ink: MistakeMapDesign.white,
        bordered: false,
      ),
      _ => (
        fill: const LinearGradient(
          begin: Alignment(-.35, -1),
          end: Alignment(.35, 1),
          colors: [MistakeMapDesign.white, Color(0xFFE7ECEE)],
          stops: [0, .7],
        ),
        ink: MistakeMapDesign.abyss,
        bordered: true,
      ),
    };

// ─── Peças comuns ───────────────────────────────────────────────────────────

/// Tela do fluxo: barra do topo, conteúdo rolável e ações fixas embaixo.
class _StepFrame extends StatelessWidget {
  const _StepFrame({
    required this.children,
    required this.actions,
    this.onBack,
    this.topLabel,
  });

  final List<Widget> children;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final Widget? topLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (onBack != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _RoundBack(onPressed: onBack!),
                ),
              ?topLabel,
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        ...actions,
      ],
    ),
  );
}

class _RoundBack extends StatelessWidget {
  const _RoundBack({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => HoverButton(
    onPressed: onPressed,
    semanticLabel: 'Voltar',
    builder: (context, states) => AnimatedContainer(
      duration: _d(context, 160),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: states.contains(WidgetState.hovered)
            ? MistakeMapDesign.white
            : const Color(0xB3FFFFFF),
        border: Border.all(
          color: states.contains(WidgetState.focused)
              ? MistakeMapDesign.azureInk
              : MistakeMapDesign.edge,
          width: states.contains(WidgetState.focused) ? 2 : 1,
        ),
      ),
      child: const Icon(
        FluentIcons.chevron_left,
        size: 14,
        color: MistakeMapDesign.abyss,
      ),
    ),
  );
}

enum _CtaKind { dark, accent, ghost }

/// Botão em pílula do protótipo; ocupado, encolhe e mostra três pontos.
class _Cta extends StatelessWidget {
  const _Cta({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = _CtaKind.dark,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final _CtaKind kind;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = switch (kind) {
      _CtaKind.accent => (MistakeMapDesign.aqua, MistakeMapDesign.abyss),
      _CtaKind.ghost => (const Color(0xBFFFFFFF), MistakeMapDesign.abyss),
      _CtaKind.dark => (MistakeMapDesign.abyss, MistakeMapDesign.white),
    };
    final enabled = onPressed != null && !busy;
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: HoverButton(
          onPressed: enabled ? onPressed : null,
          semanticLabel: busy ? 'Gerando' : label,
          builder: (context, states) {
            final hovered = states.contains(WidgetState.hovered);
            final pressed = states.contains(WidgetState.pressed);
            final color = !enabled && !busy
                ? (kind == _CtaKind.ghost
                      ? const Color(0x99FFFFFF)
                      : MistakeMapDesign.disabledFill)
                : pressed
                ? MistakeMapDesign.pressedFill(fill)
                : hovered
                ? (kind == _CtaKind.dark
                      ? MistakeMapDesign.deep
                      : MistakeMapDesign.hoverFill(fill))
                : fill;
            return AnimatedContainer(
              duration: _d(context, 450),
              curve: const Cubic(.2, .8, .2, 1),
              height: 52,
              width: busy ? 96 : constraints.maxWidth,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(26),
                border: kind == _CtaKind.ghost
                    ? Border.all(color: MistakeMapDesign.edge)
                    : states.contains(WidgetState.focused)
                    ? Border.all(color: MistakeMapDesign.azureInk, width: 2)
                    : null,
              ),
              child: busy
                  ? _BusyDots(color: ink)
                  : Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled ? ink : MistakeMapDesign.disabledInk,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _BusyDots extends StatefulWidget {
  const _BusyDots({required this.color});

  final Color color;

  @override
  State<_BusyDots> createState() => _BusyDotsState();
}

class _BusyDotsState extends State<_BusyDots>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 5,
      children: [
        for (var i = 0; i < 3; i++)
          Builder(
            builder: (context) {
              final t = (_controller.value - i * .15) % 1;
              final lift = t < .4 ? t / .4 : (t < .8 ? (.8 - t) / .4 : 0.0);
              return Transform.translate(
                offset: Offset(0, -4 * lift),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: .5 + .5 * lift),
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );
}

/// Painel de vidro com linhas chave/valor separadas por fio.
class _Panel extends StatelessWidget {
  const _Panel({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => GlassSurface(
    radius: 18,
    blur: true,
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          DecoratedBox(
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : const Border(
                      top: BorderSide(color: MistakeMapDesign.hairline),
                    ),
            ),
            child: rows[i],
          ),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.total = false});

  final String label;
  final Widget value;
  final bool total;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: total ? MistakeMapDesign.abyss : MistakeMapDesign.steel,
                fontWeight: total ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 10),
          DefaultTextStyle.merge(
            textAlign: TextAlign.right,
            style: TextStyle(
              color: MistakeMapDesign.abyss,
              fontWeight: FontWeight.w600,
              fontSize: total ? 18 : 14,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            child: value,
          ),
        ],
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: InfoBar(
      title: const Text('Vamos tentar de novo'),
      content: Text(text),
      severity: InfoBarSeverity.warning,
    ),
  );
}

/// Marca do MistakeMap: quatro nós ligados, como no ícone do app.
class _MapMark extends StatelessWidget {
  const _MapMark({required this.color, this.width = 46, this.colors});

  final Color color;
  final double width;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, width * 34 / 46),
    painter: _MapMarkPainter(color, colors),
  );
}

class _MapMarkPainter extends CustomPainter {
  const _MapMarkPainter(this.color, this.colors);

  final Color color;
  final List<Color>? colors;

  static const _points = [
    Offset(6, 26),
    Offset(17, 11),
    Offset(28, 21),
    Offset(40, 7),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 46);
    final line = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(_points.first.dx, _points.first.dy)
        ..lineTo(_points[1].dx, _points[1].dy)
        ..lineTo(_points[2].dx, _points[2].dy)
        ..lineTo(_points[3].dx, _points[3].dy),
      line,
    );
    for (var i = 0; i < _points.length; i++) {
      canvas.drawCircle(
        _points[i],
        4,
        Paint()..color = colors == null ? color : colors![i],
      );
    }
  }

  @override
  bool shouldRepaint(_MapMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.colors != colors;
}

/// Cartão do plano: gradiente, brilho a 135° e a marca no rodapé.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, this.compact = false});

  final CheckoutPlan plan;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final look = _planLook(plan.id);
    final ink = look.ink;
    final brand = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            'MISTAKEMAP',
            style: TextStyle(
              color: ink.withValues(alpha: .9),
              fontSize: 11,
              letterSpacing: .7,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _MapMark(color: ink),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 18 : 22),
        gradient: look.fill,
        border: look.bordered ? Border.all(color: MistakeMapDesign.edge) : null,
        boxShadow: _cardShadow,
      ),
      // Brilho a 135° por baixo do texto, para não lavar a tinta.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 18 : 22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x8CFFFFFF), Color(0x00FFFFFF)],
            stops: [0, .45],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 18),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      plan.name,
                      style: TextStyle(
                        color: ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    brand,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      plan.name,
                      style: TextStyle(
                        color: ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      // Fontes maiores (acessibilidade) cortam a lista, não o preço.
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          maxHeight: double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final feature in plan.features)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        margin: const EdgeInsets.only(
                                          top: 6,
                                          right: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: ink.withValues(alpha: .7),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          feature,
                                          style: TextStyle(
                                            color: ink == MistakeMapDesign.white
                                                ? ink
                                                : MistakeMapDesign.deep,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Text(
                      plan.priceLabel,
                      style: TextStyle(
                        color: ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      plan.priceNote,
                      style: TextStyle(
                        color: ink == MistakeMapDesign.white
                            ? ink
                            : MistakeMapDesign.slate,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    brand,
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── 1. Escolha do plano ────────────────────────────────────────────────────

class _PlanStep extends StatefulWidget {
  const _PlanStep({
    required this.schoolName,
    required this.index,
    required this.onIndex,
    required this.onBack,
    required this.onChoose,
    this.currentPlanId,
  });

  final String schoolName;
  final int index;
  final String? currentPlanId;
  final ValueChanged<int> onIndex;
  final VoidCallback onBack;
  final VoidCallback onChoose;

  @override
  State<_PlanStep> createState() => _PlanStepState();
}

class _PlanStepState extends State<_PlanStep> {
  late final _pages = PageController(
    initialPage: widget.index,
    viewportFraction: .62,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(int index) {
    final target = index.clamp(0, checkoutPlans.length - 1);
    _pages.animateToPage(
      target,
      duration: _d(context, 700),
      curve: const Cubic(.2, .8, .2, 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = checkoutPlans[widget.index];
    final isCurrent = current.id == widget.currentPlanId;
    return _StepFrame(
      onBack: widget.onBack,
      topLabel: Padding(
        padding: const EdgeInsets.only(left: 52),
        child: Text(
          widget.schoolName.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _eyebrow,
        ),
      ),
      actions: [
        _Cta(
          key: const Key('checkout-choose'),
          label: isCurrent
              ? 'Continuar no ${current.name}'
              : 'Escolher ${current.name}',
          onPressed: widget.onChoose,
        ),
      ],
      children: [
        const SizedBox(height: 6),
        const Text('Escolha o plano', style: _display),
        const SizedBox(height: 4),
        const Text(
          'Você paga só pelos alunos que usaram o app no mês. '
          'Professores não pagam.',
          style: _sub,
        ),
        const SizedBox(height: 14),
        _PlanLabels(index: widget.index),
        SizedBox(
          height: 22,
          child: AnimatedOpacity(
            opacity: isCurrent ? 1 : 0,
            duration: _d(context, 200),
            child: const Center(
              child: Text(
                'Seu plano atual',
                key: Key('checkout-current-plan'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: MistakeMapDesign.aquaInk,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 336,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  _select(widget.index + 1),
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  _select(widget.index - 1),
            },
            child: Focus(
              child: Semantics(
                label: 'Planos. Use as setas para trocar.',
                child: ScrollConfiguration(
                  // Arrastar com o mouse também troca o plano (web e Windows).
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: PointerDeviceKind.values.toSet(),
                    scrollbars: false,
                  ),
                  child: PageView.builder(
                    controller: _pages,
                    clipBehavior: Clip.none,
                    itemCount: checkoutPlans.length,
                    onPageChanged: widget.onIndex,
                    itemBuilder: (context, i) => AnimatedBuilder(
                      animation: _pages,
                      builder: (context, child) {
                        final page =
                            _pages.hasClients && _pages.position.haveDimensions
                            ? _pages.page!
                            : widget.index.toDouble();
                        final o = (i - page).clamp(-1.5, 1.5);
                        final side = o.abs().clamp(0.0, 1.0);
                        return Opacity(
                          opacity: (1 - .3 * side).clamp(0.0, 1.0),
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, .0011)
                              ..rotateY(o * -1.08)
                              ..scaleByDouble(
                                1 - .18 * side,
                                1 - .18 * side,
                                1,
                                1,
                              ),
                            child: child,
                          ),
                        );
                      },
                      child: GestureDetector(
                        onTap: i == widget.index ? null : () => _select(i),
                        child: Semantics(
                          button: true,
                          selected: i == widget.index,
                          label: 'Plano ${checkoutPlans[i].name}',
                          child: Center(
                            child: SizedBox(
                              width: 224,
                              height: 312,
                              child: _PlanCard(plan: checkoutPlans[i]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _Pager(count: checkoutPlans.length, index: widget.index),
      ],
    );
  }
}

class _PlanLabels extends StatelessWidget {
  const _PlanLabels({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 30,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: 14,
      children: [
        for (var i = 0; i < checkoutPlans.length; i++)
          if ((i - index).abs() <= 1)
            AnimatedDefaultTextStyle(
              duration: _d(context, 400),
              // Mescla com o estilo herdado para manter a fonte do app.
              style: DefaultTextStyle.of(context).style.merge(
                TextStyle(
                  color: i == index
                      ? MistakeMapDesign.abyss
                      : MistakeMapDesign.steel.withValues(alpha: .75),
                  fontSize: i == index ? 20 : 16,
                  fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              child: Text(checkoutPlans[i].name),
            ),
      ],
    ),
  );
}

class _Pager extends StatelessWidget {
  const _Pager({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    spacing: 6,
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: _d(context, 300),
          width: i == index ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: i == index ? MistakeMapDesign.abyss : MistakeMapDesign.pearl,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    ],
  );
}

// ─── 2. Confirmação ─────────────────────────────────────────────────────────

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({
    required this.quote,
    required this.busy,
    required this.error,
    required this.onBack,
    required this.onStudents,
    required this.onCycle,
    required this.onMethod,
    required this.savedCardLast4,
    required this.useSavedCard,
    required this.onUseSavedCard,
    required this.cardName,
    required this.cardNumber,
    required this.cardExpiry,
    required this.cardCcv,
    required this.onPay,
  });

  final CheckoutQuote quote;
  final bool busy;
  final String? error;
  final VoidCallback onBack;
  final ValueChanged<int> onStudents;
  final ValueChanged<CheckoutCycle> onCycle;
  final ValueChanged<CheckoutMethod> onMethod;
  final String? savedCardLast4;
  final bool useSavedCard;
  final ValueChanged<bool> onUseSavedCard;
  final TextEditingController cardName;
  final TextEditingController cardNumber;
  final TextEditingController cardExpiry;
  final TextEditingController cardCcv;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final plan = quote.plan;
    final card = quote.method == CheckoutMethod.creditCard;
    final payLabel = plan.isFree
        ? 'Continuar no Grátis'
        : '${switch (quote.method) {
            CheckoutMethod.pix => 'Gerar Pix',
            CheckoutMethod.boleto => 'Gerar boleto',
            CheckoutMethod.creditCard => 'Pagar',
          }} · ${formatBrl(quote.total)}';
    return _StepFrame(
      onBack: busy ? null : onBack,
      actions: [
        _Cta(
          key: const Key('checkout-pay'),
          label: payLabel,
          kind: _CtaKind.dark,
          busy: busy,
          onPressed: onPay,
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: _d(context, 250),
          child: Row(
            key: ValueKey(busy),
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 6,
            children: [
              const Icon(
                FluentIcons.lock,
                size: 12,
                color: MistakeMapDesign.steel,
              ),
              Flexible(
                child: Text(
                  busy
                      ? (card
                            ? 'Confirmando seu pagamento…'
                            : 'Gerando a cobrança no Asaas…')
                      : 'Pagamento processado pelo Asaas. Nota fiscal '
                            'emitida após a confirmação.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: MistakeMapDesign.steel,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      children: [
        const SizedBox(height: 6),
        const Text('Confirmar assinatura', style: _display),
        const SizedBox(height: 4),
        Text(
          plan.isFree
              ? 'A escola já começa no Grátis. Nada é cobrado.'
              : 'Revise antes de pagar.',
          style: _sub,
        ),
        const SizedBox(height: 14),
        SizedBox(height: 118, child: _PlanCard(plan: plan, compact: true)),
        const SizedBox(height: 12),
        _Panel(
          rows: [
            _Row(
              'Alunos ativos (estimativa)',
              _Stepper(
                value: quote.students,
                enabled: !plan.isFree && !busy,
                onChanged: onStudents,
              ),
            ),
            if (!plan.isFree)
              _Row(
                'Ciclo',
                GlassSegmented<CheckoutCycle>(
                  accent: MistakeMapDesign.aqua,
                  ink: MistakeMapDesign.aquaInk,
                  selected: quote.cycle,
                  onSelected: busy ? (_) {} : onCycle,
                  segments: const [
                    (
                      value: CheckoutCycle.monthly,
                      label: Text('Mensal'),
                      icon: null,
                      key: Key('checkout-monthly'),
                    ),
                    (
                      value: CheckoutCycle.annual,
                      label: Text('Anual'),
                      icon: null,
                      key: Key('checkout-annual'),
                    ),
                  ],
                ),
              ),
            _Row(
              'Preço por aluno',
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Text(formatBrl(quote.pricePerStudent)),
                  if (!plan.isFree && quote.cycle == CheckoutCycle.annual)
                    Text(
                      '−${plan.annualDiscountPercent}%',
                      style: const TextStyle(
                        fontSize: 11,
                        color: MistakeMapDesign.mintInk,
                      ),
                    ),
                ],
              ),
            ),
            if (quote.volumeDiscountPercent > 0)
              _Row(
                'Desconto por volume',
                Text(
                  '−${quote.volumeDiscountPercent}% · '
                  '−${formatBrl(quote.discount)}',
                  key: const Key('checkout-volume'),
                  style: const TextStyle(color: MistakeMapDesign.mintInk),
                ),
              ),
            if (!plan.isFree)
              _Row(
                'Pagamento',
                GlassSegmented<CheckoutMethod>(
                  accent: MistakeMapDesign.aqua,
                  ink: MistakeMapDesign.aquaInk,
                  selected: quote.method,
                  onSelected: busy ? (_) {} : onMethod,
                  segments: const [
                    (
                      value: CheckoutMethod.pix,
                      label: Text('Pix'),
                      icon: null,
                      key: Key('checkout-pix'),
                    ),
                    (
                      value: CheckoutMethod.boleto,
                      label: Text('Boleto'),
                      icon: null,
                      key: Key('checkout-boleto'),
                    ),
                    (
                      value: CheckoutMethod.creditCard,
                      label: Text('Cartão'),
                      icon: null,
                      key: Key('checkout-card'),
                    ),
                  ],
                ),
              ),
            _Row(
              quote.cycle == CheckoutCycle.annual && !plan.isFree
                  ? 'Total hoje (por mês, plano anual)'
                  : 'Total hoje',
              Text(
                '${formatBrl(quote.total)}${quote.atMinimum ? ' (mínimo)' : ''}',
                key: const Key('checkout-total'),
              ),
              total: true,
            ),
          ],
        ),
        if (card && !plan.isFree) ...[
          const SizedBox(height: 14),
          _CardForm(
            enabled: !busy,
            savedLast4: savedCardLast4,
            useSaved: useSavedCard,
            onUseSaved: onUseSavedCard,
            name: cardName,
            number: cardNumber,
            expiry: cardExpiry,
            ccv: cardCcv,
          ),
        ],
        if (error != null) _Notice(error!),
      ],
    );
  }
}

/// Dados do cartão. Vão direto ao servidor, que repassa ao Asaas; o app não
/// guarda nada e limpa número e código depois da tentativa.
class _CardForm extends StatelessWidget {
  const _CardForm({
    required this.enabled,
    required this.savedLast4,
    required this.useSaved,
    required this.onUseSaved,
    required this.name,
    required this.number,
    required this.expiry,
    required this.ccv,
  });

  final bool enabled;
  final String? savedLast4;
  final bool useSaved;
  final ValueChanged<bool> onUseSaved;
  final TextEditingController name;
  final TextEditingController number;
  final TextEditingController expiry;
  final TextEditingController ccv;

  @override
  Widget build(BuildContext context) {
    final saved = savedLast4 != null && useSaved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        ListenableBuilder(
          listenable: Listenable.merge([name, number, expiry]),
          builder: (context, _) => _CardFace(
            holder: saved ? '' : name.text,
            number: saved ? '•••• •••• •••• $savedLast4' : number.text,
            expiry: saved ? '' : expiry.text,
          ),
        ),
        if (savedLast4 != null)
          Checkbox(
            key: const Key('checkout-saved-card'),
            checked: useSaved,
            onChanged: enabled ? (v) => onUseSaved(v ?? false) : null,
            content: Text('Usar o cartão salvo final $savedLast4'),
          ),
        if (!saved)
          GlassSurface(
            radius: 18,
            blur: true,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                InfoLabel(
                  label: 'Nome impresso no cartão',
                  child: TextBox(
                    key: const Key('checkout-card-name'),
                    controller: name,
                    enabled: enabled,
                    textCapitalization: TextCapitalization.characters,
                    autofillHints: const [AutofillHints.creditCardName],
                  ),
                ),
                InfoLabel(
                  label: 'Número do cartão',
                  child: TextBox(
                    key: const Key('checkout-card-number'),
                    controller: number,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.creditCardNumber],
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                      LengthLimitingTextInputFormatter(23),
                    ],
                  ),
                ),
                Row(
                  spacing: 10,
                  children: [
                    Expanded(
                      child: InfoLabel(
                        label: 'Validade (MM/AA)',
                        child: TextBox(
                          key: const Key('checkout-card-expiry'),
                          controller: expiry,
                          enabled: enabled,
                          placeholder: 'MM/AA',
                          keyboardType: TextInputType.number,
                          autofillHints: const [
                            AutofillHints.creditCardExpirationDate,
                          ],
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9/]'),
                            ),
                            LengthLimitingTextInputFormatter(7),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: InfoLabel(
                        label: 'Código (CVV)',
                        child: TextBox(
                          key: const Key('checkout-card-ccv'),
                          controller: ccv,
                          enabled: enabled,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          autofillHints: const [
                            AutofillHints.creditCardSecurityCode,
                          ],
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const Text(
                  'O titular da cobrança é a escola (CNPJ, e-mail, CEP e '
                  'telefone dos dados de cobrança). O MistakeMap guarda só '
                  'um token do Asaas para as próximas faturas.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: MistakeMapDesign.steel,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Cartão físico desenhado (filosofia do protótipo: dinheiro com tato).
class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.holder,
    required this.number,
    required this.expiry,
  });

  final String holder;
  final String number;
  final String expiry;

  @override
  Widget build(BuildContext context) {
    final digits = number.replaceAll(RegExp(r'[^0-9•]'), '');
    final shown = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i > 0 && i % 4 == 0) shown.write(' ');
      shown.write(i < digits.length ? digits[i] : '•');
    }
    final brand = CheckoutCard(
      holderName: '',
      number: number,
      expiryMonth: '',
      expiryYear: '',
      ccv: '',
    ).brand;
    const ink = MistakeMapDesign.white;
    return Semantics(
      label: 'Cartão',
      child: AspectRatio(
        aspectRatio: 1.586,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment(-1, -1),
              end: Alignment(1, 1),
              colors: [
                Color(0xFF253745),
                MistakeMapDesign.abyss,
                Color(0xFF1B2A35),
              ],
              stops: [0, .55, 1],
            ),
            boxShadow: _cardShadow,
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: ink),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _MapMark(
                      color: ink,
                      width: 28,
                      colors: [
                        MistakeMapDesign.aqua,
                        MistakeMapDesign.azure,
                        MistakeMapDesign.violet,
                        MistakeMapDesign.amber,
                      ],
                    ),
                    const Spacer(),
                    Text(
                      brand,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 34,
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE9D9A6), Color(0xFFBFA45E)],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  shown.toString(),
                  style: const TextStyle(
                    fontSize: 18,
                    letterSpacing: 1.6,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        holder.isEmpty
                            ? 'NOME NO CARTÃO'
                            : holder.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                    Text(
                      expiry.isEmpty ? 'MM/AA' : expiry,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatefulWidget {
  const _Stepper({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_Stepper> createState() => _StepperState();
}

class _StepperState extends State<_Stepper> {
  late final _field = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_Stepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _field.text != '${widget.value}') {
      _field.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final typed = int.tryParse(_field.text) ?? widget.value;
    final next = typed.clamp(5, maxCheckoutStudents);
    _field.text = '$next';
    if (next != widget.value) widget.onChanged(next);
  }

  /// Passo cresce com a escola: 5 até 100, 50 até 1.000 e 100 acima.
  int get _step => widget.value < 100
      ? 5
      : widget.value < 1000
      ? 50
      : 100;

  Widget _button(String glyph, String label, int next) => HoverButton(
    onPressed: widget.enabled && next != widget.value
        ? () => widget.onChanged(next)
        : null,
    semanticLabel: label,
    builder: (context, states) => Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: states.contains(WidgetState.hovered)
            ? MistakeMapDesign.hover
            : MistakeMapDesign.white,
        border: Border.all(
          color: states.contains(WidgetState.focused)
              ? MistakeMapDesign.azureInk
              : MistakeMapDesign.edge,
        ),
      ),
      child: Text(
        glyph,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: widget.enabled
              ? MistakeMapDesign.abyss
              : MistakeMapDesign.mist,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final down = widget.value <= 100 ? 5 : (widget.value <= 1000 ? 50 : 100);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        _button('−', 'Menos $down alunos', math.max(5, widget.value - down)),
        SizedBox(
          width: 64,
          child: TextBox(
            key: const Key('checkout-students'),
            controller: _field,
            focusNode: _focus,
            enabled: widget.enabled,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(5),
            ],
            onSubmitted: (_) => _commit(),
          ),
        ),
        _button(
          '+',
          'Mais $_step alunos',
          math.min(maxCheckoutStudents, widget.value + _step),
        ),
      ],
    );
  }
}

// ─── 3. Pix ou boleto ───────────────────────────────────────────────────────

class _ChargeStep extends StatefulWidget {
  const _ChargeStep({
    required this.charge,
    required this.paid,
    required this.error,
    required this.onBack,
    required this.onCheck,
  });

  final CheckoutCharge charge;
  final bool paid;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback onCheck;

  @override
  State<_ChargeStep> createState() => _ChargeStepState();
}

class _ChargeStepState extends State<_ChargeStep>
    with TickerProviderStateMixin {
  late final _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final _check = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );
  late Duration _left = widget.charge.expiresIn;
  Timer? _timer;
  bool _copied = false;

  bool get _pix => widget.charge.quote.method == CheckoutMethod.pix;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draw.status == AnimationStatus.dismissed) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _draw.value = 1;
      } else {
        _draw.forward();
      }
      if (_pix) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() {
            if (_left > Duration.zero) _left -= const Duration(seconds: 1);
          });
        });
      }
    }
  }

  @override
  void didUpdateWidget(_ChargeStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paid && !oldWidget.paid) {
      _timer?.cancel();
      if (MediaQuery.disableAnimationsOf(context)) {
        _check.value = 1;
      } else {
        _check.forward(from: 0);
      }
    } else if (!widget.paid && oldWidget.paid) {
      _check.value = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _draw.dispose();
    _check.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.charge.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _copied = false);
  }

  String get _expiry {
    if (!_pix) return 'Vence em ${widget.charge.expiresIn.inDays} dias';
    if (_left.inHours > 0) {
      return 'Expira em ${_left.inHours}h${(_left.inMinutes % 60).toString().padLeft(2, '0')}';
    }
    final m = _left.inMinutes.toString().padLeft(2, '0');
    final s = (_left.inSeconds % 60).toString().padLeft(2, '0');
    return 'Expira em $m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final paid = widget.paid;
    final qr = widget.charge.qrImage;
    return _StepFrame(
      onBack: paid ? null : widget.onBack,
      actions: [
        _Cta(
          key: const Key('checkout-check'),
          label: paid
              ? 'Pagamento confirmado pelo Asaas'
              : 'Já paguei, conferir',
          kind: _CtaKind.ghost,
          onPressed: paid ? null : widget.onCheck,
        ),
        const SizedBox(height: 6),
        Text(
          paid
              ? 'Liberando o plano…'
              : 'A tela confere sozinha a cada poucos segundos.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, color: MistakeMapDesign.steel),
        ),
      ],
      children: [
        const SizedBox(height: 6),
        Text(_pix ? 'Pague com Pix' : 'Pague o boleto', style: _display),
        const SizedBox(height: 4),
        Text(
          _pix ? 'Abra o app do banco e leia o código.' : 'Use a linha digitável ou baixe o PDF. Compensa em até 1 dia útil.',
          style: _sub,
        ),
        const SizedBox(height: 14),
        Center(
          child: Container(
            width: 230,
            height: 230,
            decoration: BoxDecoration(
              color: MistakeMapDesign.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: MistakeMapDesign.edge),
              boxShadow: _cardShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Semantics(
                  label: _pix ? 'QR Code do Pix' : 'Código de barras do boleto',
                  child: _pix && qr != null
                      ? FadeTransition(
                          opacity: _draw,
                          child: Image.memory(
                            qr,
                            key: const Key('checkout-qr'),
                            width: 204,
                            height: 204,
                            filterQuality: FilterQuality.none,
                            gaplessPlayback: true,
                          ),
                        )
                      : _pix
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Use o Pix copia e cola abaixo no app do banco.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: MistakeMapDesign.steel),
                          ),
                        )
                      : FadeTransition(
                          opacity: _draw,
                          child: const Padding(
                            padding: EdgeInsets.all(26),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              spacing: 10,
                              children: [
                                SizedBox(
                                  height: 90,
                                  child: CustomPaint(
                                    size: Size(170, 90),
                                    painter: _BarcodePainter(),
                                  ),
                                ),
                                Text(
                                  'Boleto registrado no Asaas',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: MistakeMapDesign.steel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                IgnorePointer(
                  child: AnimatedOpacity(
                    duration: _d(context, 400),
                    opacity: paid ? 1 : 0,
                    child: Container(
                      color: const Color(0xE0FFFFFF),
                      alignment: Alignment.center,
                      child: AnimatedBuilder(
                        animation: _check,
                        builder: (context, _) => CustomPaint(
                          size: const Size.square(96),
                          painter: _CheckPainter(_check.value),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: _StatusPill(
            ok: paid,
            label: paid
                ? 'Pagamento confirmado'
                : (_pix ? 'Aguardando pagamento' : 'Aguardando compensação'),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: MistakeMapDesign.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MistakeMapDesign.edge),
          ),
          child: Row(
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  widget.charge.code,
                  key: const Key('checkout-code'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono.copyWith(
                    fontSize: 11,
                    height: 1.2,
                    color: MistakeMapDesign.slate,
                  ),
                ),
              ),
              HoverButton(
                onPressed: _copy,
                semanticLabel: _pix
                    ? 'Copiar código Pix'
                    : 'Copiar linha digitável',
                builder: (context, states) => AnimatedContainer(
                  duration: _d(context, 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: states.contains(WidgetState.hovered)
                        ? MistakeMapDesign.deep
                        : MistakeMapDesign.abyss,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _copied ? 'Copiado' : 'Copiar',
                    style: const TextStyle(
                      color: MistakeMapDesign.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        DefaultTextStyle.merge(
          style: const TextStyle(
            fontSize: 12,
            color: MistakeMapDesign.steel,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text('Valor ${formatBrl(widget.charge.quote.total)}'),
              ),
              const SizedBox(width: 8),
              Text(_expiry),
            ],
          ),
        ),
        if (!_pix && widget.charge.bankSlipUrl != null) ...[
          const SizedBox(height: 10),
          Center(
            child: HyperlinkButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: widget.charge.bankSlipUrl!),
              ),
              child: const Text('Copiar link do PDF do boleto'),
            ),
          ),
        ],
        if (widget.error != null) _Notice(widget.error!),
      ],
    );
  }
}

class _StatusPill extends StatefulWidget {
  const _StatusPill({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  State<_StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<_StatusPill>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_StatusPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.ok || MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (bg, ink, dot) = widget.ok
        ? (
            MistakeMapDesign.mint.withValues(alpha: .18),
            MistakeMapDesign.mintInk,
            MistakeMapDesign.mint,
          )
        : (
            MistakeMapDesign.amber.withValues(alpha: .18),
            MistakeMapDesign.amberInk,
            MistakeMapDesign.amber,
          );
    return Semantics(
      liveRegion: true,
      child: AnimatedContainer(
        duration: _d(context, 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = math.sin(_pulse.value * math.pi);
                return Transform.scale(
                  scale: 1 - .2 * t,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dot.withValues(alpha: 1 - .65 * t),
                    ),
                  ),
                );
              },
            ),
            Text(
              widget.label,
              style: TextStyle(
                color: ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// QR ilustrativo (37 × 37): os módulos surgem aos poucos e os três
/// localizadores e o centro Aqua entram no fim.
class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    final circle = (t / .63).clamp(0.0, 1.0);
    final tick = ((t - .53) / .47).clamp(0.0, 1.0);
    canvas.drawCircle(
      const Offset(50, 50),
      45,
      Paint()..color = MistakeMapDesign.mint.withValues(alpha: .14 * circle),
    );
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(50, 50), radius: 45),
      -math.pi / 2,
      2 * math.pi * circle,
      false,
      Paint()
        ..color = MistakeMapDesign.mint
        ..strokeWidth = 6
        ..style = PaintingStyle.stroke,
    );
    if (tick == 0) return;
    final path = Path()
      ..moveTo(30, 52)
      ..lineTo(43, 65)
      ..lineTo(70, 36);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * tick),
      Paint()
        ..color = MistakeMapDesign.mintInk
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => oldDelegate.t != t;
}

// ─── 4. Plano ativado ───────────────────────────────────────────────────────

class _ActivatedStep extends StatefulWidget {
  const _ActivatedStep({
    required this.receipt,
    required this.onReceipt,
    required this.onDone,
  });

  final CheckoutReceipt receipt;
  final VoidCallback onReceipt;
  final VoidCallback onDone;

  @override
  State<_ActivatedStep> createState() => _ActivatedStepState();
}

class _ActivatedStepState extends State<_ActivatedStep>
    with SingleTickerProviderStateMixin {
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.status == AnimationStatus.dismissed) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _intro.value = 1;
      } else {
        _intro.forward();
      }
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quote = widget.receipt.quote;
    final card = widget.receipt.cardLast4;
    return _StepFrame(
      actions: [
        _Cta(
          key: const Key('checkout-receipt'),
          label: 'Ver recibo',
          kind: _CtaKind.ghost,
          onPressed: widget.onReceipt,
        ),
        const SizedBox(height: 10),
        _Cta(label: 'Concluir', onPressed: widget.onDone),
      ],
      children: [
        SizedBox(
          height: 230,
          child: Semantics(
            label: 'Maquininha com o pagamento aprovado',
            child: AnimatedBuilder(
              animation: _intro,
              builder: (context, _) => CustomPaint(
                painter: _TerminalPainter(_intro.value),
                size: const Size(300, 230),
              ),
            ),
          ),
        ),
        FadeTransition(
          opacity: CurvedAnimation(
            parent: _intro,
            curve: const Interval(.45, 1, curve: Curves.easeOut),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pagamento confirmado',
                textAlign: TextAlign.center,
                style: _display,
              ),
              const SizedBox(height: 4),
              Text(
                'Plano ${quote.plan.name} ativo. Os alunos já podem entrar '
                'pelo código da turma. A nota fiscal sai pelo Asaas para o '
                'e-mail de cobrança.',
                textAlign: TextAlign.center,
                style: _sub,
              ),
              const SizedBox(height: 14),
              _Panel(
                rows: [
                  _Row('Pago', Text(formatBrl(quote.total))),
                  _Row(
                    'Forma',
                    Text(
                      card == null
                          ? quote.method.label
                          : '${quote.method.label} final $card',
                    ),
                  ),
                  _Row(
                    'Válido até',
                    Text(formatDate(widget.receipt.periodEnd)),
                  ),
                  _Row(
                    'Próxima fatura',
                    Text(formatDate(widget.receipt.nextInvoice)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Maquininha isométrica em traço (protótipo de referência): o cartão
/// entra, a tela acende o check verde e o comprovante sai por trás.
class _TerminalPainter extends CustomPainter {
  const _TerminalPainter(this.t);

  final double t;

  static const _c = 0.866; // cos 30°
  static const _line = MistakeMapDesign.abyss;

  Offset _iso(Size size, double x, double y, double z) => Offset(
    size.width / 2 + (x - y) * _c,
    size.height * .62 + (x + y) * .5 - z,
  );

  Path _poly(Size size, List<(double, double, double)> pts) {
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final (x, y, z) = pts[i];
      final o = _iso(size, x, y, z);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    return path..close();
  }

  void _face(Canvas canvas, Path path, Color fill) {
    canvas
      ..drawPath(path, Paint()..color = fill)
      ..drawPath(
        path,
        Paint()
          ..color = _line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cardIn = Curves.easeOutCubic.transform((t / .4).clamp(0.0, 1.0));
    final paper = Curves.easeOut.transform(((t - .55) / .45).clamp(0.0, 1.0));
    final check = ((t - .3) / .4).clamp(0.0, 1.0);

    // Sombra no chão.
    canvas.drawPath(
      _poly(size, [
        (-62, -40, 0),
        (62, -40, 0),
        (62, 40, 0),
        (-62, 40, 0),
      ]).shift(const Offset(0, 10)),
      Paint()
        ..color = const Color(0x2211212D)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Comprovante saindo por trás (antes do corpo, para ficar atrás).
    if (paper > 0) {
      final h = 70 * paper;
      _face(
        canvas,
        _poly(size, [
          (-30, -34, 22),
          (30, -34, 22),
          (30, -34, 22 + h),
          (-30, -34, 22 + h),
        ]),
        MistakeMapDesign.white,
      );
      final lines = Paint()
        ..color = MistakeMapDesign.mist
        ..strokeWidth = 1.2;
      for (var k = 1; k <= 4; k++) {
        final z = 22 + h - k * 12;
        if (z <= 26) break;
        canvas.drawLine(
          _iso(size, -22, -34, z),
          _iso(size, k.isEven ? 10 : 20, -34, z),
          lines,
        );
      }
    }

    // Corpo: laterais e topo.
    const w = 60.0, d = 38.0, h = 22.0;
    _face(
      canvas,
      _poly(size, [(-w, d, 0), (w, d, 0), (w, d, h), (-w, d, h)]),
      const Color(0xFFDDE3E5),
    );
    _face(
      canvas,
      _poly(size, [(w, -d, 0), (w, d, 0), (w, d, h), (w, -d, h)]),
      const Color(0xFFC9D1D4),
    );
    _face(
      canvas,
      _poly(size, [(-w, -d, h), (w, -d, h), (w, d, h), (-w, d, h)]),
      MistakeMapDesign.white,
    );

    // Tela.
    _face(
      canvas,
      _poly(size, [(-48, -30, h), (8, -30, h), (8, 4, h), (-48, 4, h)]),
      check > 0 ? const Color(0xFF0F2A22) : MistakeMapDesign.deep,
    );
    if (check > 0) {
      final center = _iso(size, -20, -13, h);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(1, .58);
      canvas.drawCircle(
        Offset.zero,
        18 * Curves.easeOutBack.transform(check),
        Paint()..color = MistakeMapDesign.mint,
      );
      if (check > .5) {
        final tick = ((check - .5) / .5).clamp(0.0, 1.0);
        final path = Path()
          ..moveTo(-8, 0)
          ..lineTo(-2, 6)
          ..lineTo(9, -6);
        final metric = path.computeMetrics().first;
        canvas.drawPath(
          metric.extractPath(0, metric.length * tick),
          Paint()
            ..color = MistakeMapDesign.white
            ..strokeWidth = 3.4
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke,
        );
      }
      canvas.restore();
    }

    // Teclado 3 × 3.
    for (var r = 0; r < 3; r++) {
      for (var col = 0; col < 3; col++) {
        final x = 18.0 + col * 12, y = -26.0 + r * 11;
        _face(
          canvas,
          _poly(size, [
            (x, y, h),
            (x + 8, y, h),
            (x + 8, y + 7, h),
            (x, y + 7, h),
          ]),
          r == 2 && col == 2 ? MistakeMapDesign.mint : MistakeMapDesign.canvas,
        );
      }
    }

    // Cartão entrando pela frente.
    final slide = 70 * (1 - cardIn);
    _face(
      canvas,
      _poly(size, [
        (-34, d + 4 + slide, 14),
        (34, d + 4 + slide, 14),
        (34, d + 4 + slide + 46, 14),
        (-34, d + 4 + slide + 46, 14),
      ]),
      MistakeMapDesign.aqua,
    );
    canvas.drawLine(
      _iso(size, -26, d + 14 + slide, 14),
      _iso(size, 10, d + 14 + slide, 14),
      Paint()
        ..color = MistakeMapDesign.abyss
        ..strokeWidth = 3,
    );
    // Fenda por cima do cartão.
    canvas.drawLine(
      _iso(size, -38, d, 14),
      _iso(size, 38, d, 14),
      Paint()
        ..color = _line
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TerminalPainter oldDelegate) => oldDelegate.t != t;
}

// ─── 5. Recibo ──────────────────────────────────────────────────────────────

class _ReceiptStep extends StatefulWidget {
  const _ReceiptStep({
    required this.receipt,
    required this.schoolName,
    required this.onBack,
    required this.onDone,
  });

  final CheckoutReceipt receipt;
  final String schoolName;
  final VoidCallback onBack;
  final VoidCallback onDone;

  @override
  State<_ReceiptStep> createState() => _ReceiptStepState();
}

class _ReceiptStepState extends State<_ReceiptStep>
    with SingleTickerProviderStateMixin {
  // 2,6 s de papel saindo e o carimbo em 2,8 s.
  late final _print = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3150),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_print.status == AnimationStatus.dismissed) _start();
  }

  void _start() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _print.value = 1;
    } else {
      _print.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _print.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final quote = receipt.quote;
    final plan = quote.plan;
    final paper = CurvedAnimation(
      parent: _print,
      curve: const Interval(0, .825, curve: Cubic(.3, .1, .2, 1)),
    );
    final stamp = CurvedAnimation(
      parent: _print,
      curve: const Interval(.889, 1, curve: Cubic(.3, 1.6, .4, 1)),
    );
    return _StepFrame(
      onBack: widget.onBack,
      topLabel: const Text('RECIBO', style: _eyebrow),
      actions: [
        AnimatedBuilder(
          animation: _print,
          builder: (context, _) => Semantics(
            liveRegion: true,
            child: Text(
              _print.value >= .889 ? 'Recibo pronto' : 'Imprimindo seu recibo…',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: MistakeMapDesign.steel,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: _Cta(
                label: 'Imprimir de novo',
                kind: _CtaKind.ghost,
                onPressed: _start,
              ),
            ),
            Expanded(
              child: _Cta(label: 'Concluir', onPressed: widget.onDone),
            ),
          ],
        ),
      ],
      children: [
        const SizedBox(height: 4),
        // Única área escura do fluxo, como no protótipo: o recibo é o
        // objeto em destaque.
        Container(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
          decoration: BoxDecoration(
            color: MistakeMapDesign.abyss,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 280,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [MistakeMapDesign.white, Color(0xFFE4E9EB)],
                    ),
                    border: Border.all(color: MistakeMapDesign.edge),
                    boxShadow: _cardShadow,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 12,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: MistakeMapDesign.deep,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 16,
                        top: 10,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: MistakeMapDesign.aqua,
                            boxShadow: [
                              BoxShadow(
                                color: MistakeMapDesign.aqua,
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -14),
                child: Center(
                  child: SizedBox(
                    width: 246,
                    child: AnimatedBuilder(
                      animation: _print,
                      builder: (context, child) => ClipRect(
                        child: Align(
                          // O papel sai pela fenda: aparece primeiro o rodapé.
                          alignment: Alignment.bottomCenter,
                          heightFactor: paper.value,
                          child: child,
                        ),
                      ),
                      child: Stack(
                        children: [
                          _Paper(
                            receipt: receipt,
                            schoolName: widget.schoolName,
                            planLine:
                                'Plano ${plan.name} ${quote.cycle == CheckoutCycle.annual ? 'anual' : 'mensal'}',
                          ),
                          Positioned(
                            right: 14,
                            bottom: 58,
                            child: AnimatedBuilder(
                              animation: stamp,
                              builder: (context, child) => Opacity(
                                opacity: _print.value < .889 ? 0 : .92,
                                child: Transform.rotate(
                                  angle: -16 * math.pi / 180,
                                  child: Transform.scale(
                                    scale: 2.2 - 1.2 * stamp.value,
                                    child: child,
                                  ),
                                ),
                              ),
                              child: const _Stamp(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Paper extends StatelessWidget {
  const _Paper({
    required this.receipt,
    required this.schoolName,
    required this.planLine,
  });

  final CheckoutReceipt receipt;
  final String schoolName;
  final String planLine;

  @override
  Widget build(BuildContext context) {
    final quote = receipt.quote;
    final plan = quote.plan;
    Widget line(String a, String b, {bool total = false}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      spacing: 8,
      children: [
        Flexible(child: Text(a)),
        Flexible(child: Text(b, textAlign: TextAlign.right)),
      ],
    );
    final total = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: MistakeMapDesign.abyss,
      fontFamily: _mono.fontFamily,
      fontFamilyFallback: _mono.fontFamilyFallback,
    );
    final caption = _mono.copyWith(
      fontSize: 9.5,
      height: 1.4,
      letterSpacing: 1.3,
      color: MistakeMapDesign.steel,
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Color(0x8011212D),
            blurRadius: 24,
            spreadRadius: -14,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipPath(
        clipper: const _ScallopClipper(),
        child: ColoredBox(
          color: MistakeMapDesign.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 26),
            child: DefaultTextStyle.merge(
              style: _mono,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 6,
                    children: [
                      _MapMark(
                        color: MistakeMapDesign.abyss,
                        width: 22,
                        colors: [
                          MistakeMapDesign.aqua,
                          MistakeMapDesign.azure,
                          MistakeMapDesign.violet,
                          MistakeMapDesign.amber,
                        ],
                      ),
                      Text(
                        'MISTAKEMAP',
                        style: TextStyle(
                          fontFamily: null,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.8,
                          color: MistakeMapDesign.abyss,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'RECIBO DE PAGAMENTO',
                    textAlign: TextAlign.center,
                    style: caption,
                  ),
                  const _Dashed(),
                  line('Recibo', receipt.number),
                  line('Data', formatDateTime(receipt.paidAt)),
                  line('Escola', schoolName),
                  const _Dashed(),
                  line(
                    planLine,
                    plan.isFree
                        ? '—'
                        : '${quote.students} × ${formatBrl(quote.pricePerStudent)}',
                  ),
                  if (quote.volumeDiscountPercent > 0)
                    line(
                      'Desconto volume −${quote.volumeDiscountPercent}%',
                      '−${formatBrl(quote.discount)}',
                    ),
                  line(
                    'Período',
                    '${formatDate(receipt.periodStart).substring(0, 5)} a '
                        '${formatDate(receipt.periodEnd)}',
                  ),
                  line('Professores', 'grátis'),
                  line(
                    'Cota de análises',
                    formatThousands(quote.analysesQuota),
                  ),
                  const _Dashed(),
                  DefaultTextStyle.merge(
                    style: total,
                    child: line('TOTAL', formatBrl(quote.total)),
                  ),
                  line(
                    receipt.cardLast4 == null
                        ? quote.method.label
                        : '${quote.method.label} •••• ${receipt.cardLast4}',
                    'via Asaas',
                  ),
                  line(
                    'NFS-e',
                    receipt.invoiceNumber.isEmpty
                        ? 'em emissão'
                        : 'nº ${receipt.invoiceNumber}',
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(
                    height: 34,
                    child: CustomPaint(painter: _BarcodePainter()),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    receipt.transactionId,
                    textAlign: TextAlign.center,
                    style: caption,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Obrigado por ensinar com o MistakeMap.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: null,
                      fontStyle: FontStyle.italic,
                      fontSize: 11.5,
                      color: MistakeMapDesign.slate,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dashed extends StatelessWidget {
  const _Dashed();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 9),
    child: SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashPainter()),
    ),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MistakeMapDesign.mist
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(math.min(x + 3, size.width), 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => false;
}

class _BarcodePainter extends CustomPainter {
  const _BarcodePainter();

  // Mesmo padrão do protótipo: barras de 2, 1 e 3 px a cada 11 px.
  static const _bars = [(0.0, 2.0), (3.0, 1.0), (7.0, 3.0)];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = MistakeMapDesign.abyss;
    for (double x = 0; x < size.width; x += 11) {
      for (final (start, width) in _bars) {
        final left = x + start;
        if (left >= size.width) break;
        canvas.drawRect(
          Rect.fromLTWH(
            left,
            0,
            math.min(width, size.width - left),
            size.height,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter oldDelegate) => false;
}

/// Base serrilhada do papel térmico: meias-luas de 5 px a cada 12 px.
class _ScallopClipper extends CustomClipper<Path> {
  const _ScallopClipper();

  @override
  Path getClip(Size size) {
    const step = 12.0, r = 5.0;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height);
    for (var x = size.width; x > 0; x -= step) {
      final left = math.max(0.0, x - step);
      final mid = (x + left) / 2;
      path
        ..lineTo(math.min(x, mid + r), size.height)
        ..arcToPoint(
          Offset(math.max(left, mid - r), size.height),
          radius: const Radius.circular(r),
        )
        ..lineTo(left, size.height);
    }
    return path..close();
  }

  @override
  bool shouldReclip(_ScallopClipper oldClipper) => false;
}

class _Stamp extends StatelessWidget {
  const _Stamp();

  @override
  Widget build(BuildContext context) => Container(
    width: 78,
    height: 78,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: MistakeMapDesign.mint.withValues(alpha: .08),
      border: Border.all(color: MistakeMapDesign.mintInk, width: 3),
    ),
    child: Container(
      margin: const EdgeInsets.all(4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: MistakeMapDesign.mintInk.withValues(alpha: .6),
        ),
      ),
      child: const Text(
        'PAGO',
        style: TextStyle(
          color: MistakeMapDesign.mintInk,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.7,
        ),
      ),
    ),
  );
}

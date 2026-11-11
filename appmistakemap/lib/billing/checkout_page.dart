import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';

import '../theme/design_tokens.dart';
import '../theme/glass_surface.dart';
import 'checkout_models.dart';

/// Assinatura da escola, do plano ao recibo (protótipo "Checkout
/// MistakeMap"): escolha do plano em carrossel 3D, confirmação, Pix ou
/// boleto, plano ativado e recibo impresso com o carimbo de pago.
///
/// Os dados vêm de [CheckoutGateway]. Sem gateway, a tela usa o simulado e
/// avisa que é uma prévia: nada é cobrado.
class SchoolCheckoutPage extends StatefulWidget {
  const SchoolCheckoutPage({
    super.key,
    this.schoolName = 'Escola Exemplo de Robótica',
    this.gateway,
  });

  final String schoolName;
  final CheckoutGateway? gateway;

  @override
  State<SchoolCheckoutPage> createState() => _SchoolCheckoutPageState();
}

class _SchoolCheckoutPageState extends State<SchoolCheckoutPage> {
  late final CheckoutGateway _gateway =
      widget.gateway ?? SimulatedCheckoutGateway();
  late final bool _preview = widget.gateway == null;

  int _step = 0;
  bool _forward = true;
  int _planIndex = 1;
  int _students = 30;
  CheckoutCycle _cycle = CheckoutCycle.annual;
  CheckoutMethod _method = CheckoutMethod.pix;
  bool _busy = false;
  bool _paid = false;
  CheckoutCharge? _charge;
  CheckoutReceipt? _receipt;
  String? _error;

  CheckoutPlan get _plan => checkoutPlans[_planIndex];

  CheckoutQuote get _quote => _gateway.quote(
    plan: _plan,
    students: _students,
    cycle: _cycle,
    method: _method,
  );

  void _go(int step) => setState(() {
    _forward = step > _step;
    _step = step;
    _error = null;
  });

  void _back() {
    if (_step == 0) {
      Navigator.maybePop(context);
      return;
    }
    // Do recibo volta para o plano ativado; da cobrança, para a confirmação.
    _go(_step - 1);
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final charge = await _gateway.createCharge(_quote);
      if (!mounted) return;
      _charge = charge;
      _paid = false;
      if (charge.quote.plan.isFree) {
        _receipt = await _gateway.confirm(charge);
        if (!mounted) return;
        _go(3);
      } else {
        _go(2);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não deu para gerar a cobrança agora.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final charge = _charge;
    if (charge == null || _paid) return;
    setState(() => _paid = true);
    try {
      final receipt = await _gateway.confirm(charge);
      if (!mounted) return;
      _receipt = receipt;
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      if (mounted && _step == 2) _go(3);
    } catch (_) {
      if (mounted) {
        setState(() {
          _paid = false;
          _error = 'O pagamento ainda não foi confirmado.';
        });
      }
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
      preview: _preview,
      index: _planIndex,
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
      onMethod: (m) => setState(() => _method = m),
      onPay: _generate,
    ),
    2 => _ChargeStep(
      charge: _charge!,
      paid: _paid,
      preview: _preview,
      error: _error,
      onBack: _back,
      onSimulate: _confirm,
    ),
    3 => _ActivatedStep(
      receipt: _receipt!,
      onReceipt: () => _go(4),
      onDone: () => Navigator.maybePop(context),
    ),
    _ => _ReceiptStep(
      receipt: _receipt!,
      schoolName: widget.schoolName,
      preview: _preview,
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
    required this.preview,
    required this.index,
    required this.onIndex,
    required this.onBack,
    required this.onChoose,
  });

  final String schoolName;
  final bool preview;
  final int index;
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
    return _StepFrame(
      onBack: widget.onBack,
      topLabel: Padding(
        padding: const EdgeInsets.only(left: 52),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.schoolName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _eyebrow,
              ),
            ),
            if (widget.preview) const _PreviewTag(),
          ],
        ),
      ),
      actions: [
        _Cta(
          key: const Key('checkout-choose'),
          label: 'Escolher ${current.name}',
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

class _PreviewTag extends StatelessWidget {
  const _PreviewTag();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Prévia: nenhum pagamento é feito.',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: MistakeMapDesign.amber.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Prévia',
        style: TextStyle(
          color: MistakeMapDesign.amberInk,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
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
    required this.onPay,
  });

  final CheckoutQuote quote;
  final bool busy;
  final String? error;
  final VoidCallback onBack;
  final ValueChanged<int> onStudents;
  final ValueChanged<CheckoutCycle> onCycle;
  final ValueChanged<CheckoutMethod> onMethod;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final plan = quote.plan;
    final payLabel = plan.isFree
        ? 'Ativar plano Grátis'
        : '${quote.method == CheckoutMethod.pix ? 'Gerar Pix' : 'Gerar boleto'}'
              ' · ${formatBrl(quote.total)}';
    return _StepFrame(
      onBack: busy ? null : onBack,
      actions: [
        _Cta(
          key: const Key('checkout-pay'),
          label: payLabel,
          kind: _CtaKind.accent,
          busy: busy,
          onPressed: onPay,
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 6,
          children: [
            Icon(FluentIcons.lock, size: 12, color: MistakeMapDesign.steel),
            Flexible(
              child: Text(
                'Nota fiscal emitida junto com o pagamento',
                style: TextStyle(fontSize: 11.5, color: MistakeMapDesign.steel),
              ),
            ),
          ],
        ),
      ],
      children: [
        const SizedBox(height: 6),
        const Text('Confirmar assinatura', style: _display),
        const SizedBox(height: 4),
        const Text('Confira antes de gerar a cobrança.', style: _sub),
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
                ],
              ),
            ),
            _Row(
              'Total por mês',
              Text(
                '${formatBrl(quote.total)}${quote.atMinimum ? ' (mínimo)' : ''}',
                key: const Key('checkout-total'),
              ),
              total: true,
            ),
          ],
        ),
        if (error != null) _Notice(error!),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  Widget _button(String glyph, String label, int next) => HoverButton(
    onPressed: enabled && next != value ? () => onChanged(next) : null,
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
          color: enabled ? MistakeMapDesign.abyss : MistakeMapDesign.mist,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 8,
    children: [
      _button('−', 'Menos 5 alunos', math.max(5, value - 5)),
      SizedBox(
        width: 32,
        child: Text(
          '$value',
          key: const Key('checkout-students'),
          textAlign: TextAlign.center,
        ),
      ),
      _button('+', 'Mais 5 alunos', math.min(500, value + 5)),
    ],
  );
}

// ─── 3. Pix ou boleto ───────────────────────────────────────────────────────

class _ChargeStep extends StatefulWidget {
  const _ChargeStep({
    required this.charge,
    required this.paid,
    required this.preview,
    required this.error,
    required this.onBack,
    required this.onSimulate,
  });

  final CheckoutCharge charge;
  final bool paid;
  final bool preview;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback onSimulate;

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
    final m = _left.inMinutes.toString().padLeft(2, '0');
    final s = (_left.inSeconds % 60).toString().padLeft(2, '0');
    return 'Expira em $m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final paid = widget.paid;
    final simulateLabel = paid
        ? (widget.preview ? 'Pagamento simulado' : 'Confirmado pelo webhook')
        : (widget.preview ? 'Simular pagamento' : 'Já paguei');
    return _StepFrame(
      onBack: paid ? null : widget.onBack,
      actions: [
        _Cta(
          key: const Key('checkout-simulate'),
          label: simulateLabel,
          kind: _CtaKind.ghost,
          onPressed: paid ? null : widget.onSimulate,
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
                  label: _pix
                      ? 'QR Code ilustrativo do Pix'
                      : 'Código de barras ilustrativo do boleto',
                  child: AnimatedBuilder(
                    animation: _draw,
                    builder: (context, _) => CustomPaint(
                      size: const Size.square(196),
                      painter: _QrPainter(progress: _draw.value),
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
        if (widget.preview) ...[
          const SizedBox(height: 10),
          const Text(
            'Prévia: o código é ilustrativo e nenhum pagamento é feito.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: MistakeMapDesign.steel),
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
class _QrPainter extends CustomPainter {
  _QrPainter({required this.progress});

  final double progress;

  static const _n = 37;
  static final List<(int, int)> _cells = () {
    var seed = 20261111;
    double next() {
      seed = (seed * 1103515245 + 12345) % 2147483648;
      return seed / 2147483648;
    }

    bool finder(int i, int j) =>
        (i < 8 && j < 8) || (i < 8 && j > _n - 9) || (i > _n - 9 && j < 8);
    return [
      for (var i = 0; i < _n; i++)
        for (var j = 0; j < _n; j++)
          if (!finder(i, j) && next() > .52) (i, j),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final m = size.width / _n;
    final ink = Paint()..color = MistakeMapDesign.abyss;
    final white = Paint()..color = MistakeMapDesign.white;
    Rect cell(num x, num y, num w) => Rect.fromLTWH(x * m, y * m, w * m, w * m);
    void finder(int x, int y) {
      canvas
        ..drawRect(cell(x, y, 7), ink)
        ..drawRect(cell(x + 1, y + 1, 5), white)
        ..drawRect(cell(x + 2, y + 2, 3), ink);
    }

    finder(0, 0);
    finder(_n - 7, 0);
    finder(0, _n - 7);
    final shown = (_cells.length * progress).round();
    for (var k = 0; k < shown; k++) {
      final (i, j) = _cells[k];
      // Um pouco maior que o módulo para não deixar fios entre vizinhos.
      canvas.drawRect(Rect.fromLTWH(j * m, i * m, m + .4, m + .4), ink);
    }
    if (progress >= 1) {
      canvas
        ..drawRect(cell(16, 16, 5), Paint()..color = MistakeMapDesign.aqua)
        ..drawRect(cell(17, 17, 3), white)
        ..drawRect(cell(18, 18, 1), ink);
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Círculo Mint que se fecha e o visto que se desenha por cima.
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

  static const _sparkColors = [
    MistakeMapDesign.aqua,
    MistakeMapDesign.azure,
    MistakeMapDesign.violet,
    MistakeMapDesign.amber,
    MistakeMapDesign.mint,
  ];

  @override
  Widget build(BuildContext context) {
    final quote = widget.receipt.quote;
    final badge = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0, .58, curve: Cubic(.2, 1.4, .3, 1)),
    );
    final sparks = CurvedAnimation(
      parent: _intro,
      curve: const Interval(.25, 1, curve: Curves.easeOut),
    );
    return _StepFrame(
      actions: [
        _Cta(
          key: const Key('checkout-receipt'),
          label: 'Ver recibo e nota fiscal',
          kind: _CtaKind.ghost,
          onPressed: widget.onReceipt,
        ),
        const SizedBox(height: 10),
        _Cta(label: 'Ir para o painel da escola', onPressed: widget.onDone),
      ],
      children: [
        SizedBox(
          height: 230,
          child: AnimatedBuilder(
            animation: _intro,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (sparks.value > 0 && sparks.value < 1)
                  for (var i = 0; i < 14; i++)
                    Builder(
                      builder: (context) {
                        final a = i / 14 * 2 * math.pi;
                        final t = sparks.value;
                        return Transform.translate(
                          offset: Offset(
                            math.cos(a) * 120 * t,
                            math.sin(a) * 100 * t,
                          ),
                          child: Transform.scale(
                            scale: 1 - .6 * t,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _sparkColors[i % 5].withValues(
                                  alpha: 1 - t,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                Opacity(
                  opacity: _intro.value.clamp(0.0, .3) / .3,
                  child: Transform.rotate(
                    angle: -8 * math.pi / 180,
                    child: Transform.scale(
                      scale: .6 + .4 * badge.value,
                      child: Container(
                        width: 150,
                        height: 150,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(40),
                          gradient: _planLook('escola').fill,
                          boxShadow: _cardShadow,
                        ),
                        child: const _MapMark(
                          color: MistakeMapDesign.abyss,
                          width: 96,
                          colors: [
                            MistakeMapDesign.white,
                            MistakeMapDesign.white,
                            MistakeMapDesign.white,
                            MistakeMapDesign.white,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          'Plano ${quote.plan.name} ativo',
          textAlign: TextAlign.center,
          style: _display,
        ),
        const SizedBox(height: 4),
        const Text(
          'Os alunos já podem entrar pelo código da turma. A nota fiscal foi '
          'enviada para o e-mail do financeiro.',
          textAlign: TextAlign.center,
          style: _sub,
        ),
        const SizedBox(height: 14),
        _Panel(
          rows: [
            _Row('Pago', Text(formatBrl(quote.total))),
            _Row('Alunos liberados', Text('${quote.releasedStudents}')),
            _Row(
              'Próxima fatura',
              Text(formatDate(widget.receipt.nextInvoice)),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── 5. Recibo ──────────────────────────────────────────────────────────────

class _ReceiptStep extends StatefulWidget {
  const _ReceiptStep({
    required this.receipt,
    required this.schoolName,
    required this.preview,
    required this.onBack,
    required this.onDone,
  });

  final CheckoutReceipt receipt;
  final String schoolName;
  final bool preview;
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
              _print.value >= .889
                  ? 'Recibo e NFS-e prontos'
                  : 'Imprimindo o recibo…',
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
                        BoxShadow(color: MistakeMapDesign.aqua, blurRadius: 8),
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
                      preview: widget.preview,
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
    );
  }
}

class _Paper extends StatelessWidget {
  const _Paper({
    required this.receipt,
    required this.schoolName,
    required this.preview,
    required this.planLine,
  });

  final CheckoutReceipt receipt;
  final String schoolName;
  final bool preview;
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
                  if (preview)
                    Text(
                      'PRÉVIA · SEM VALOR FISCAL',
                      textAlign: TextAlign.center,
                      style: caption.copyWith(color: MistakeMapDesign.amberInk),
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
                    quote.method == CheckoutMethod.pix ? 'Pix' : 'Boleto',
                    'via Asaas',
                  ),
                  line('NFS-e', 'nº ${receipt.invoiceNumber}'),
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

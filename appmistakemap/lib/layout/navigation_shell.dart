import 'package:fluent_ui/fluent_ui.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../theme/control_styles.dart';
import '../theme/design_tokens.dart';
import '../theme/glass_surface.dart';
import '../theme/motion.dart';
import 'adaptativo.dart';

// Acrílico Fluent no trilho lateral: topo mais opaco, base mais translúcida.
const _railGradient = MistakeMapDesign.acrylic;
const _hoverFill = Color(0x0F11212D);

/// Navigation owns its space: no content is painted underneath its buttons.
class AppNavigationShell extends StatelessWidget {
  const AppNavigationShell({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.onAbout,
    this.onStudy,
    this.onSignOut,
    this.onAnalysis,
    required this.hasAdmin,
    required this.child,
  });

  /// Ação principal (analisar um exercício), à vista em todo tamanho de tela:
  /// no celular, botão redondo de vidro ao lado da cápsula (como a busca da
  /// barra do iOS 26); no trilho, o primeiro controle, no lugar do FAB do
  /// NavigationRail do Material 3.
  final VoidCallback? onAnalysis;

  /// Destino atual. Tocar de novo no destino atual também chama
  /// [onSelected], para a página voltar à raiz.
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onAbout;

  /// Atalho para o Estudar, que mora dentro do Mapa.
  final VoidCallback? onStudy;

  /// Sair da conta fica junto das outras opções, não escondido numa tela.
  final VoidCallback? onSignOut;
  final bool hasAdmin;
  final Widget child;

  static const labels = [
    'Início',
    'Meus exercícios',
    'Mapa de erros',
    'Caderno de erros',
    'Administração',
  ];

  /// Cada destino tem seu acento Aurora: a cor diz onde o aluno está.
  static const accents = [
    MistakeMapDesign.aqua,
    MistakeMapDesign.azure,
    MistakeMapDesign.violet,
    MistakeMapDesign.amber,
    MistakeMapDesign.mint,
  ];

  /// O mesmo acento escurecido, para ícones legíveis sobre o vidro branco.
  static const accentInks = [
    MistakeMapDesign.aquaInk,
    MistakeMapDesign.azureInk,
    MistakeMapDesign.violetInk,
    MistakeMapDesign.amberInk,
    MistakeMapDesign.mintInk,
  ];
  static const icons = [
    WindowsIcons.home,
    WindowsIcons.bulleted_list,
    WindowsIcons.relationship,
    WindowsIcons.quick_note,
    WindowsIcons.admin,
  ];

  ButtonStyle _style(
    bool selected, {
    bool compact = false,
    Color accent = MistakeMapDesign.mist,
  }) => ButtonStyle(
    textStyle: WidgetStatePropertyAll(
      TextStyle(fontSize: compact ? 12 : 14, fontWeight: FontWeight.w600),
    ),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: compact ? 4 : 12, vertical: 10),
    ),
    shape: WidgetStateProperty.resolveWith(
      (states) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: states.contains(WidgetState.focused)
            ? const BorderSide(color: MistakeMapDesign.aquaInk, width: 2)
            : BorderSide(
                // A aba atual fica marcada mesmo sem foco: borda e fundo
                // no acento do destino.
                // Na barra inferior a aba atual é marcada pela pílula que
                // desliza por trás dos botões, não pelo botão.
                color: selected && !compact
                    ? accent.withValues(alpha: .55)
                    : states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.pressed)
                    ? MistakeMapDesign.edge
                    : Colors.transparent,
              ),
      ),
    ),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      // Opaco: a sombra da aba atual não pode aparecer através do fundo.
      if (selected && !compact) {
        return Color.alphaBlend(
          accent.withValues(alpha: .16),
          MistakeMapDesign.white,
        );
      }
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.hovered)) {
        return _hoverFill;
      }
      return Colors.transparent;
    }),
    foregroundColor: const WidgetStatePropertyAll(MistakeMapDesign.content),
    // A sombra da aba atual vem da superfície; sobre o vidro líquido a sombra
    // padrão do botão escurecia as abas em repouso.
    elevation: const WidgetStatePropertyAll(0),
  );

  Duration _motionDuration(
    BuildContext context, [
    Duration duration = MistakeMapMotion.controls,
  ]) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

  /// Every destination uses the same clear surface as the Home control.
  Widget _surface(
    BuildContext context,
    bool selected,
    Widget child, {
    bool compact = false,
  }) => AnimatedContainer(
    duration: _motionDuration(context),
    curve: MistakeMapMotion.curve,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      boxShadow: selected && !compact
          ? const [
              BoxShadow(
                color: Color(0x1F11212D),
                blurRadius: 14,
                spreadRadius: -6,
                offset: Offset(0, 6),
              ),
            ]
          : null,
    ),
    // Fluent animates hover/press decoration with its faster duration.
    // Keep that state handling inside the button, away from page rebuilds.
    child: FluentTheme(
      data: FluentTheme.of(context).copyWith(
        fasterAnimationDuration: _motionDuration(
          context,
          MistakeMapMotion.hover,
        ),
        fastAnimationDuration: _motionDuration(context, MistakeMapMotion.hover),
        animationCurve: MistakeMapMotion.hoverCurve,
      ),
      child: child,
    ),
  );

  Widget _icon(
    BuildContext context,
    IconData icon,
    bool selected, {
    bool compact = false,
    Color accent = MistakeMapDesign.mist,
    Color ink = MistakeMapDesign.steel,
  }) => _NavigationIcon(
    icon: icon,
    selected: selected,
    compact: compact,
    accent: accent,
    ink: ink,
  );

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.9,
        color: MistakeMapDesign.steel,
      ),
    ),
  );

  /// A pílula da aba atual na cápsula e no trilho compacto: o acento do
  /// destino sobre vidro claro.
  static BoxDecoration _pill(Color accent) => BoxDecoration(
    color: Color.alphaBlend(
      accent.withValues(alpha: .22),
      const Color(0xC7FFFFFF),
    ),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: accent.withValues(alpha: .55)),
    boxShadow: [
      BoxShadow(
        color: accent.withValues(alpha: .35),
        blurRadius: 16,
        spreadRadius: -6,
        offset: const Offset(0, 6),
      ),
    ],
  );

  /// No trilho compacto não há espaço medido para a pílula deslizar: ela
  /// acende no próprio destino.
  Widget _pilled(
    BuildContext context, {
    required bool selected,
    required Color accent,
    required Widget child,
  }) => AnimatedContainer(
    duration: _motionDuration(context),
    curve: MistakeMapMotion.curve,
    decoration: selected
        ? _pill(accent)
        : BoxDecoration(borderRadius: BorderRadius.circular(12)),
    child: child,
  );

  Widget _destination(
    BuildContext context,
    int index, {
    required bool compact,
  }) {
    final selected = index == selectedIndex;
    final accent = accents[index];
    final icon = _icon(
      context,
      icons[index],
      selected,
      compact: compact,
      accent: accent,
      ink: accentInks[index],
    );
    final text = Text(
      compact
          ? const ['Início', 'Lista', 'Mapa', 'Caderno'][index]
          : labels[index],
      textAlign: compact ? TextAlign.center : TextAlign.start,
      maxLines: compact ? 1 : null,
      softWrap: !compact,
      style: TextStyle(
        fontSize: compact ? 12 : 14,
        fontWeight: FontWeight.w600,
      ),
    );
    // Em telas de 320 px a barra inferior encolhe o rótulo em vez de quebrá-lo.
    final label = compact
        ? FittedBox(fit: BoxFit.scaleDown, child: text)
        : text;
    return Semantics(
      selected: selected,
      child: Tooltip(
        message: 'Ir para ${labels[index]}',
        child: _surface(
          context,
          selected,
          Button(
            key: ValueKey('navigation-$index'),
            style: _style(selected, compact: compact, accent: accent),
            onPressed: () => onSelected(index),
            child: _NavigationHoverInk(
              selected: selected,
              compact: compact,
              child: compact
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [icon, const SizedBox(height: 8), label],
                    )
                  : Row(
                      children: [
                        icon,
                        const SizedBox(width: 12),
                        Expanded(child: label),
                        SizedBox(
                          width: 12,
                          child: selected
                              ? Icon(
                                  WindowsIcons.chevron_right,
                                  size: 12,
                                  color: accentInks[index],
                                )
                              : null,
                        ),
                      ],
                    ),
            ),
          ),
          compact: compact,
        ),
      ),
    );
  }

  void _openAfterMenu(BuildContext context, VoidCallback action) {
    // Fluent starts closing its flyout before calling the menu item's action.
    // Wait for that pop to finish before a new page becomes the current route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) action();
    });
  }

  MenuFlyoutItemBase _flyoutItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback action,
    bool selected = false,
  }) => MenuFlyoutItemBuilder(
    builder: (menuContext) => _surface(
      menuContext,
      selected,
      Button(
        style: _style(selected),
        onPressed: () {
          Navigator.of(menuContext).maybePop();
          _openAfterMenu(context, action);
        },
        child: _NavigationHoverInk(
          selected: selected,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _icon(menuContext, icon, selected),
                const SizedBox(width: 12),
                Flexible(child: Text(label, textAlign: TextAlign.start)),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _more(BuildContext context) => Semantics(
    selected: selectedIndex == 4,
    child: DropDownButton(
      title: const Text('Mais'),
      leading: const Icon(WindowsIcons.more, size: 20),
      menuColor: MistakeMapDesign.white,
      menuShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: MistakeMapDesign.border),
      ),
      buttonBuilder: (context, open) => Tooltip(
        message: 'Mais opções de navegação',
        child: _surface(
          context,
          selectedIndex == 4,
          Button(
            key: const ValueKey('navigation-more'),
            style: _style(selectedIndex == 4, compact: true),
            onPressed: open,
            child: _NavigationHoverInk(
              selected: selectedIndex == 4,
              compact: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _icon(
                    context,
                    WindowsIcons.more,
                    selectedIndex == 4,
                    compact: true,
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      selectedIndex == 4 ? 'Admin' : 'Mais',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          compact: true,
        ),
      ),
      items: [
        if (hasAdmin)
          _flyoutItem(
            context,
            icon: WindowsIcons.admin,
            label: 'Admin',
            selected: selectedIndex == 4,
            action: () => onSelected(4),
          ),
        if (onStudy != null)
          _flyoutItem(
            context,
            icon: WindowsIcons.education,
            label: 'Estudar com a IA',
            action: onStudy!,
          ),
        _flyoutItem(
          context,
          icon: WindowsIcons.info,
          label: 'Sobre o App',
          action: onAbout,
        ),
        if (onSignOut != null)
          _flyoutItem(
            context,
            icon: WindowsIcons.sign_out,
            label: 'Sair',
            action: onSignOut!,
          ),
      ],
    ),
  );

  /// Cápsula da barra inferior. Com alto contraste ligado no aparelho, o
  /// vidro vira superfície sólida, como nas demais telas.
  Widget _bottomGlass(BuildContext context, Widget child) {
    if (MediaQuery.highContrastOf(context)) {
      return GlassSurface(tier: GlassTier.liquid, radius: 28, child: child);
    }
    // Vidro líquido de verdade (refração, brilho e borda) pelo
    // liquid_glass_renderer; com o Flutter GPU desligado o próprio pacote
    // troca por vidro fosco. LiquidStretch dá a física de mola: a cápsula
    // estica um pouco ao ser arrastada e volta. GlassGlowLayer pinta o brilho
    // que segue o dedo, enviado pelo GlassGlow de dentro.
    return LiquidStretch(
      interactionScale: 1.02,
      stretch: .25,
      child: GlassGlowLayer(
        child: LiquidGlass.withOwnLayer(
          useBackdropGroup: true,
          shape: const LiquidRoundedSuperellipse(borderRadius: 28),
          settings: LiquidGlassSettings.ios27Regular(
            brightness: Brightness.light,
          ),
          shadows: MistakeMapDesign.liquidShadow,
          child: child,
        ),
      ),
    );
  }

  /// Ação do trilho que abre uma página em vez de trocar de aba.
  Widget _railAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color accent = MistakeMapDesign.mist,
    Color ink = MistakeMapDesign.steel,
  }) => _surface(
    context,
    false,
    Button(
      style: _style(false),
      onPressed: onPressed,
      child: _NavigationHoverInk(
        child: Row(
          children: [
            _icon(context, icon, false, accent: accent, ink: ink),
            const SizedBox(width: 12),
            Expanded(child: Text(label, textAlign: TextAlign.start)),
            const SizedBox(width: 12),
          ],
        ),
      ),
    ),
  );

  /// Painel acrílico dos trilhos: topo mais opaco, base mais translúcida.
  Widget _railPanel(
    BuildContext context, {
    required double width,
    required Widget child,
  }) => Container(
    // Em paisagem o recorte da câmera fica à esquerda: o trilho passa por
    // baixo dele e mantém a largura útil (senão os rótulos quebram no
    // meio da palavra).
    width: width + MediaQuery.paddingOf(context).left,
    decoration: const BoxDecoration(
      gradient: _railGradient,
      border: Border(
        // Borda especular: a luz pega a aresta do painel acrílico.
        right: BorderSide(color: Color(0xE6FFFFFF)),
      ),
      boxShadow: [
        BoxShadow(
          color: Color(0x1F11212D),
          blurRadius: 28,
          offset: Offset(6, 0),
        ),
      ],
    ),
    child: Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Navegação principal',
      child: SafeArea(right: false, child: child),
    ),
  );

  /// Ação principal no trilho largo: botão cheio no acento, acima dos
  /// destinos, para não ser confundido com uma aba selecionada.
  Widget _railPrimary(BuildContext context) => Tooltip(
    message: 'Analisar um exercício',
    child: MistakeMapButton(
      key: const ValueKey('navigation-action'),
      style: MistakeMapControls.button(
        radius: 12,
        fontSize: 14,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        background: MistakeMapDesign.accent,
        foreground: MistakeMapDesign.abyss,
      ),
      onPressed: onAnalysis,
      child: const Row(
        children: [
          Icon(WindowsIcons.lightbulb, size: 18),
          SizedBox(width: 12),
          Expanded(
            child: Text('Analisar exercício', textAlign: TextAlign.start),
          ),
        ],
      ),
    ),
  );

  /// Trilho largo (janelas expandidas, a partir de 840 px): destinos com
  /// rótulo inteiro, agrupados em estudo e conta.
  Widget _expandedRail(BuildContext context) => _railPanel(
    context,
    width: 224,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          // A marca leva o gradiente Aurora escurecido; o resto do trilho fica
          // sóbrio.
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: MistakeMapDesign.hero.createShader,
            child: const Text(
              'MistakeMap',
              style: TextStyle(
                color: MistakeMapDesign.strong,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (onAnalysis != null) ...[
          _railPrimary(context),
          const SizedBox(height: 24),
        ],
        // O ciclo de estudo de cima para baixo, na ordem de uso: registrar e
        // conferir, entender o padrão, estudar e anotar. Estudar mora dentro
        // do Mapa e aparece logo abaixo dele.
        _section('SEU ESTUDO'),
        for (final i in [0, 1, 2]) ...[
          _destination(context, i, compact: false),
          const SizedBox(height: 8),
        ],
        if (onStudy != null) ...[
          _railAction(
            context,
            icon: WindowsIcons.education,
            label: 'Estudar com a IA',
            onPressed: onStudy!,
            accent: MistakeMapDesign.violet,
            ink: MistakeMapDesign.violetInk,
          ),
          const SizedBox(height: 8),
        ],
        _destination(context, 3, compact: false),
        const SizedBox(height: 24),
        _section('CONTA'),
        if (hasAdmin) ...[
          _destination(context, 4, compact: false),
          const SizedBox(height: 8),
        ],
        _railAction(
          context,
          icon: WindowsIcons.info,
          label: 'Sobre o App',
          onPressed: onAbout,
        ),
        if (onSignOut != null) ...[
          const SizedBox(height: 8),
          _railAction(
            context,
            icon: WindowsIcons.sign_out,
            label: 'Sair',
            onPressed: onSignOut!,
          ),
        ],
      ],
    ),
  );

  /// Trilho compacto (janelas médias, de 600 a 840 px: tablet em pé,
  /// dobrável aberto, celular deitado): o NavigationRail do Material 3 com o
  /// vidro do app. Os mesmos destinos e o mesmo Mais da barra inferior, sem
  /// gastar a altura, que é o que falta nessas telas.
  Widget _compactRail(BuildContext context) => _railPanel(
    context,
    width: 88,
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          if (onAnalysis != null) ...[
            _actionButton(context),
            const SizedBox(height: 16),
          ],
          for (var i = 0; i < 4; i++) ...[
            _pilled(
              context,
              selected: i == selectedIndex,
              accent: accents[i],
              child: _destination(context, i, compact: true),
            ),
            const SizedBox(height: 8),
          ],
          _pilled(
            context,
            selected: selectedIndex == 4,
            accent: accents[4],
            child: _more(context),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final width = constraints.maxWidth / scale;
      if (width >= LimitesLargura.media) {
        return AuroraBackground(
          child: Row(
            // O painel do trilho ocupa a altura toda, mesmo com poucos
            // destinos (o trilho compacto rola em vez de preencher).
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              width >= LimitesLargura.expandida
                  ? _expandedRail(context)
                  : _compactRail(context),
              // O trilho já cobre o recorte da esquerda: o conteúdo não
              // precisa recuar de novo.
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeLeft: true,
                  child: child,
                ),
              ),
            ],
          ),
        );
      }
      final withBar = MediaQuery.viewInsetsOf(context).bottom == 0;
      return AuroraBackground(
        child: Column(
          children: [
            // A barra já reserva a área de gestos: a página não soma de novo
            // esse recuo no fim da lista.
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: withBar,
                child: child,
              ),
            ),
            if (withBar)
              SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 8),
                // Cápsula de vidro líquido que flutua sobre a luz Aurora;
                // continua ocupando o próprio espaço, abaixo do conteúdo.
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    label: 'Navegação principal',
                    child: _bottomBar(
                      context,
                      // A ação principal só cabe ao lado da cápsula quando há
                      // largura para as cinco abas continuarem legíveis.
                      withAction: onAnalysis != null && width >= 360,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  /// Barra inferior no modelo das barras de abas do iOS 26 e do Material 3:
  /// cápsula flutuante de vidro, uma pílula que desliza entre as abas e se
  /// acomoda na aba atual, brilho que segue o dedo e a cápsula que estica ao
  /// ser arrastada; a ação principal fica num botão redondo separado.
  Widget _bottomBar(BuildContext context, {required bool withAction}) {
    final slot = selectedIndex.clamp(0, 4);
    final accent = accents[slot];
    final capsule = _bottomGlass(
      context,
      GlassGlow(
        glowColor: accent.withValues(alpha: .35),
        glowRadius: .9,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, box) {
              const gap = 8.0;
              final width = (box.maxWidth - gap * 4) / 5;
              return Stack(
                children: [
                  // A pílula da aba atual: mesma geometria dos botões, desliza
                  // e troca de cor com o acento do destino.
                  AnimatedPositioned(
                    duration: _motionDuration(context, MistakeMapMotion.page),
                    curve: MistakeMapMotion.curve,
                    left: slot * (width + gap),
                    top: 0,
                    bottom: 0,
                    width: width,
                    child: AnimatedContainer(
                      duration: _motionDuration(context),
                      curve: MistakeMapMotion.curve,
                      decoration: _pill(accent),
                    ),
                  ),
                  // Same 8px rhythm around and between the buttons, so each
                  // destination reads as its own control.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: gap,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Expanded(
                          child: _destination(context, i, compact: true),
                        ),
                      Expanded(child: _more(context)),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    if (!withAction) return capsule;
    // Cápsula e botão ficam sobre o mesmo conteúdo: uma captura do fundo
    // serve aos dois (sem isso, cada vidro lê a tela inteira por quadro).
    return BackdropGroup(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 8,
        children: [
          Expanded(child: capsule),
          _actionButton(context),
        ],
      ),
    );
  }

  /// Botão redondo de vidro para a ação principal, separado da cápsula.
  Widget _actionButton(BuildContext context) {
    const size = 56.0;
    final button = Tooltip(
      message: 'Analisar um exercício',
      child: Button(
        key: const ValueKey('navigation-action'),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStateProperty.resolveWith(
            (states) => CircleBorder(
              side: states.contains(WidgetState.focused)
                  ? const BorderSide(color: MistakeMapDesign.aquaInk, width: 2)
                  : BorderSide.none,
            ),
          ),
        ),
        onPressed: onAnalysis,
        child: _NavigationHoverInk(
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: _NavigationIcon(
                icon: WindowsIcons.lightbulb,
                selected: true,
                compact: false,
                accent: MistakeMapDesign.aqua,
                ink: MistakeMapDesign.aquaInk,
              ),
            ),
          ),
        ),
      ),
    );
    if (MediaQuery.highContrastOf(context)) {
      return GlassSurface(
        tier: GlassTier.liquid,
        radius: size / 2,
        child: button,
      );
    }
    return LiquidStretch(
      interactionScale: 1.04,
      stretch: .3,
      child: LiquidGlass.withOwnLayer(
        useBackdropGroup: true,
        shape: const LiquidOval(),
        settings: LiquidGlassSettings.ios27Regular(
          brightness: Brightness.light,
        ),
        shadows: MistakeMapDesign.liquidShadow,
        child: button,
      ),
    );
  }
}

/// Synchronizes content with Fluent's own hover state and fill animation.
/// Only the control subtree rebuilds; the page and its state are untouched.
class _NavigationHoverInk extends StatelessWidget {
  const _NavigationHoverInk({
    required this.child,
    this.selected = false,
    this.compact = false,
  });

  final Widget child;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final states =
        HoverButton.maybeOf(context)?.states ?? const <WidgetState>{};
    final highlighted =
        !states.contains(WidgetState.disabled) &&
        (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: highlighted || selected ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : MistakeMapMotion.hover,
      curve: MistakeMapMotion.hoverCurve,
      child: child,
      builder: (context, progress, child) {
        // Steel em repouso, Abyss no hover e na aba atual: ambos passam de
        // 4,5:1 sobre o vidro e sobre o fundo tingido pelo acento.
        final ink = Color.lerp(
          MistakeMapDesign.steel,
          MistakeMapDesign.abyss,
          progress,
        )!;
        return _NavigationHoverProgress(
          progress: progress,
          // O mesmo afundar ao toque dos demais botões do app.
          child: PressScale(
            pressed:
                !states.contains(WidgetState.disabled) &&
                states.contains(WidgetState.pressed),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: ink),
              child: IconTheme.merge(
                data: IconThemeData(color: ink),
                child: child!,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavigationHoverProgress extends InheritedWidget {
  const _NavigationHoverProgress({
    required this.progress,
    required super.child,
  });

  final double progress;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_NavigationHoverProgress>()
          ?.progress ??
      0;

  @override
  bool updateShouldNotify(_NavigationHoverProgress oldWidget) =>
      progress != oldWidget.progress;
}

class _NavigationIcon extends StatelessWidget {
  const _NavigationIcon({
    required this.icon,
    required this.selected,
    required this.compact,
    required this.accent,
    required this.ink,
  });

  final IconData icon;
  final bool selected;
  final bool compact;
  final Color accent;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final progress = selected ? 1.0 : _NavigationHoverProgress.of(context);
    return Container(
      width: compact ? 24 : 32,
      height: compact ? 24 : 32,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .16 + .14 * progress),
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        border: Border.all(
          color: accent.withValues(alpha: .35 + .3 * progress),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: .45),
                  blurRadius: 12,
                  spreadRadius: -4,
                ),
              ]
            : null,
      ),
      child: Icon(icon, size: compact ? 17 : 18, color: ink),
    );
  }
}

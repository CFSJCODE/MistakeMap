import 'package:fluent_ui/fluent_ui.dart';

import '../theme/design_tokens.dart';
import '../theme/motion.dart';

const _navigationGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFF4F9FD), Color(0xFFDCEAF8)],
);

/// Navigation owns its space: no content is painted underneath its buttons.
class AppNavigationShell extends StatelessWidget {
  const AppNavigationShell({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.onAbout,
    this.onAnalysis,
    this.onErrorMap,
    required this.hasAdmin,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onAbout;
  final VoidCallback? onAnalysis;
  final VoidCallback? onErrorMap;
  final bool hasAdmin;
  final Widget child;

  static const labels = [
    'Início',
    'Meus exercícios',
    'Mapa de erros',
    'Novo exercício',
    'Administração',
  ];
  static const icons = [
    WindowsIcons.home,
    WindowsIcons.bulleted_list,
    WindowsIcons.relationship,
    WindowsIcons.add,
    WindowsIcons.admin,
  ];

  ButtonStyle _style(bool selected, {bool compact = false}) => ButtonStyle(
    textStyle: WidgetStatePropertyAll(
      TextStyle(fontSize: compact ? 12 : 14, fontWeight: FontWeight.w600),
    ),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: compact ? 4 : 12, vertical: 10),
    ),
    shape: WidgetStateProperty.resolveWith(
      (states) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: states.contains(WidgetState.focused)
              ? MistakeMapDesign.primary
              : states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.pressed)
              ? MistakeMapDesign.primary
              : const Color(0xFFA9C6E4),
          width: states.contains(WidgetState.focused) ? 2 : 1,
        ),
      ),
    ),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      if (states.contains(WidgetState.pressed)) return MistakeMapDesign.primary;
      if (states.contains(WidgetState.hovered)) return MistakeMapDesign.primary;
      return Colors.transparent;
    }),
    foregroundColor: const WidgetStatePropertyAll(MistakeMapDesign.content),
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
      borderRadius: BorderRadius.circular(14),
      gradient: _navigationGradient,
      boxShadow: !compact
          ? const [
              BoxShadow(
                color: Color(0x101E5CA7),
                blurRadius: 8,
                offset: Offset(0, 2),
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
  }) => _NavigationIcon(icon: icon, selected: selected, compact: compact);

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: MistakeMapDesign.content,
      ),
    ),
  );

  Widget _destination(
    BuildContext context,
    int index, {
    required bool compact,
  }) {
    final selected = index == selectedIndex;
    final icon = _icon(context, icons[index], selected, compact: compact);
    final label = Text(
      compact
          ? const ['Início', 'Lista', 'Mapa', 'Novo'][index]
          : labels[index],
      textAlign: compact ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontSize: compact ? 12 : 14,
        fontWeight: FontWeight.w600,
      ),
    );
    return Semantics(
      selected: selected,
      child: Tooltip(
        message: 'Ir para ${labels[index]}',
        child: _surface(
          context,
          selected,
          Button(
            key: ValueKey('navigation-$index'),
            style: _style(selected, compact: compact),
            onPressed: index == 2 && onErrorMap != null
                ? onErrorMap
                : () => onSelected(index),
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
                              ? const Icon(WindowsIcons.chevron_right, size: 12)
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
      menuColor: MistakeMapDesign.surface,
      menuShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
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
                  Text(
                    selectedIndex == 4 ? 'Admin' : 'Mais',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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
        if (onAnalysis != null)
          _flyoutItem(
            context,
            icon: WindowsIcons.lightbulb,
            label: 'Analisar com IA',
            action: onAnalysis!,
          ),
        if (onAnalysis != null) const MenuFlyoutSeparator(),
        if (hasAdmin)
          _flyoutItem(
            context,
            icon: WindowsIcons.admin,
            label: 'Admin',
            selected: selectedIndex == 4,
            action: () => onSelected(4),
          ),
        _flyoutItem(
          context,
          icon: WindowsIcons.info,
          label: 'Sobre o App',
          action: onAbout,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final desktop = constraints.maxWidth / scale >= 840;
      if (desktop) {
        return Row(
          children: [
            Container(
              width: 224,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFBFDFE), Color(0xFFEDF4F9)],
                ),
                border: Border(
                  right: BorderSide(color: MistakeMapDesign.border),
                ),
              ),
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'MistakeMap',
                        style: TextStyle(
                          color: MistakeMapDesign.primary,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _section('ESTUDO'),
                    for (final i in [0, 1, 3]) ...[
                      _destination(context, i, compact: false),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 24),
                    _section('INTELIGÊNCIA ARTIFICIAL'),
                    if (onAnalysis != null) ...[
                      _surface(
                        context,
                        false,
                        Button(
                          style: _style(false),
                          onPressed: onAnalysis,
                          child: _NavigationHoverInk(
                            child: Row(
                              children: [
                                _icon(context, WindowsIcons.lightbulb, false),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Analisar com IA',
                                    textAlign: TextAlign.start,
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _destination(context, 2, compact: false),
                    const SizedBox(height: 24),
                    _section('SISTEMA'),
                    if (hasAdmin) ...[
                      _destination(context, 4, compact: false),
                      const SizedBox(height: 8),
                    ],
                    _surface(
                      context,
                      false,
                      Button(
                        style: _style(false),
                        onPressed: onAbout,
                        child: _NavigationHoverInk(
                          child: Row(
                            children: [
                              _icon(context, WindowsIcons.info, false),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Sobre o App',
                                  textAlign: TextAlign.start,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: child),
          ],
        );
      }
      return Column(
        children: [
          Expanded(child: child),
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFCFEFF), Color(0xFFEEF4FA)],
                ),
                border: Border(top: BorderSide(color: MistakeMapDesign.border)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0C142A4A),
                    blurRadius: 12,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                // Same 8px rhythm around and between the buttons, so each
                // destination reads as its own control.
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Expanded(
                          child: _destination(context, i, compact: true),
                        ),
                      Expanded(child: _more(context)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
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
    final original = _navigationGradient.colors;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: highlighted ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : MistakeMapMotion.hover,
      curve: MistakeMapMotion.hoverCurve,
      child: child,
      builder: (context, progress, child) {
        final fill = [
          for (final color in original)
            Color.lerp(color, MistakeMapDesign.primary, progress)!,
        ];
        final ink = _readableInk(fill);
        return _NavigationHoverProgress(
          progress: progress,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: ink),
            child: IconTheme.merge(
              data: IconThemeData(color: ink),
              child: child!,
            ),
          ),
        );
      },
    );
  }
}

/// Choose ink from the painted fill, including the middle of the transition.
/// A direct blue-to-white ink lerp becomes unreadable over a midtone fill.
Color _readableInk(List<Color> fill) {
  final darkest = fill.reduce(
    (a, b) => a.computeLuminance() < b.computeLuminance() ? a : b,
  );
  double minimumContrast(Color ink) {
    final inkLuminance = ink.computeLuminance();
    return fill
        .map((color) {
          final fillLuminance = color.computeLuminance();
          return inkLuminance > fillLuminance
              ? (inkLuminance + 0.05) / (fillLuminance + 0.05)
              : (fillLuminance + 0.05) / (inkLuminance + 0.05);
        })
        .reduce((a, b) => a < b ? a : b);
  }

  final ink = MistakeMapDesign.hoverInk(darkest, MistakeMapDesign.content);
  if (minimumContrast(ink) >= 4.5) return ink;
  // A gradient's lighter endpoint may require a later white-ink handoff.
  return minimumContrast(Colors.white) >= minimumContrast(Colors.black)
      ? Colors.white
      : Colors.black;
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
  });

  final IconData icon;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final progress = _NavigationHoverProgress.of(context);
    final color = Color.lerp(
      const Color(0xFFD2E4F7),
      MistakeMapDesign.primary,
      progress,
    )!;
    return Container(
      width: compact ? 24 : 32,
      height: compact ? 24 : 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        border: Border.all(
          color: Color.lerp(
            const Color(0xFF9EBBDD),
            const Color(0x663F80C5),
            progress,
          )!,
        ),
      ),
      child: Icon(icon, size: compact ? 17 : 18, color: _readableInk([color])),
    );
  }
}

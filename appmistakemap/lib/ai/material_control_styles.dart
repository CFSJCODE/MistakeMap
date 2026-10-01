import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/motion.dart';

/// Uses native button interaction states with one synchronized color animation.
/// Material's button fill does not interpolate with animationDuration alone.
abstract final class MistakeMapMaterialControls {
  static ButtonStyle button(
    BuildContext context, {
    Color background = MistakeMapDesign.surface,
    Color foreground = MistakeMapDesign.content,
    bool quiet = false,
    double radius = 12,
    BorderSide? border,
  }) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : MistakeMapMotion.hover;
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      animationDuration: duration,
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return const Color(0xFF61758A);
        }
        return foreground;
      }),
      // The layer below owns the fill, so the Material never snaps to a color.
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      side: const WidgetStatePropertyAll(BorderSide.none),
      backgroundBuilder: (context, states, child) => _MaterialHoverSurface(
        states: states,
        duration: duration,
        background: background,
        foreground: foreground,
        radius: radius,
        border:
            border ??
            BorderSide(
              color: quiet ? Colors.transparent : MistakeMapDesign.border,
            ),
        quiet: quiet,
        child: child ?? const SizedBox.shrink(),
      ),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    );
  }
}

class _MaterialHoverSurface extends StatelessWidget {
  const _MaterialHoverSurface({
    required this.states,
    required this.duration,
    required this.background,
    required this.foreground,
    required this.radius,
    required this.border,
    required this.quiet,
    required this.child,
  });

  final Set<WidgetState> states;
  final Duration duration;
  final Color background;
  final Color foreground;
  final double radius;
  final BorderSide border;
  final bool quiet;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final disabled = states.contains(WidgetState.disabled);
    final active =
        !disabled &&
        (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed));
    final baseFill = disabled
        ? quiet
              ? Colors.transparent
              : const Color(0xFFE5ECF2)
        : background;
    final baseInk = disabled ? const Color(0xFF61758A) : foreground;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: active ? 1 : 0),
      duration: disabled ? Duration.zero : duration,
      curve: MistakeMapMotion.hoverCurve,
      child: child,
      builder: (context, progress, child) {
        var fill = Color.lerp(baseFill, MistakeMapDesign.primary, progress)!;
        if (states.contains(WidgetState.pressed) && !disabled) {
          fill = Color.alphaBlend(const Color(0x14000000), fill);
        }
        final ink = disabled
            ? baseInk
            : MistakeMapDesign.hoverInk(
                fill,
                baseInk,
                restingFill: quiet
                    ? Theme.of(context).colorScheme.surface
                    : baseFill,
              );
        final focused = states.contains(WidgetState.focused) && !disabled;
        final outline = focused
            ? BorderSide(
                color: Color.lerp(
                  MistakeMapDesign.primary,
                  Colors.white,
                  progress,
                )!,
                width: 2,
              )
            : border.copyWith(
                color: Color.lerp(
                  border.color,
                  MistakeMapDesign.primary,
                  progress,
                ),
              );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.fromBorderSide(outline),
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: ink),
            child: ListTileTheme(
              data: ListTileTheme.of(context)
                  .copyWith(textColor: ink, iconColor: ink),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: ink),
                child: child!,
              ),
            ),
          ),
        );
      },
    );
  }
}

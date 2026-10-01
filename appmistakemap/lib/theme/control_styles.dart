import 'package:fluent_ui/fluent_ui.dart';

import 'design_tokens.dart';
import 'motion.dart';

/// Light control surfaces; labels stay on an opaque, readable background.
abstract final class MistakeMapControls {
  static ButtonStyle button({
    double radius = 12,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      vertical: 12,
      horizontal: 20,
    ),
    double fontSize = 16,
    Color? background,
    Color? foreground,
  }) {
    final fill = background ?? MistakeMapDesign.surface;
    final ink = foreground ?? MistakeMapDesign.content;
    final strong =
        ink.computeLuminance() > 0.8 && fill.computeLuminance() < 0.5;
    return ButtonStyle(
      padding: WidgetStatePropertyAll(padding),
      textStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return const Color(0xFFE5ECF2);
        }
        if (states.contains(WidgetState.pressed)) {
          return const Color(0xFF194F90);
        }
        if (states.contains(WidgetState.hovered)) {
          return MistakeMapDesign.primary;
        }
        return fill;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? const Color(0xFF61758A)
            : states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.pressed)
            ? const Color(0xFFFFFFFF)
            : ink,
      ),
      shape: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: const BorderSide(color: MistakeMapDesign.primary, width: 2),
          );
        }
        return RoundedRectangleGradientBorder(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: strong
                ? [const Color(0x66FFFFFF), const Color(0x33214572)]
                : [const Color(0xFFFFFFFF), MistakeMapDesign.border],
          ),
        );
      }),
      elevation: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.disabled) ||
                states.contains(WidgetState.pressed)
            ? 0
            : 1,
      ),
      shadowColor: const WidgetStatePropertyAll(Color(0x12142A4A)),
    );
  }

  static ShapeBorder get menuShape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: const BorderSide(color: MistakeMapDesign.border),
  );
}

/// Keep Fluent's actions and semantics, while painting ink and fill together.
/// SDK BaseButton animates text and background separately and snaps IconTheme.
mixin _MistakeMapButtonMotion on BaseButton {
  ButtonStyle motionStyleOf(BuildContext context) =>
      defaultStyleOf(context).merge(themeStyleOf(context))!.merge(style)!;

  @override
  State<BaseButton> createState() => _MistakeMapButtonState();
}

class MistakeMapButton extends Button with _MistakeMapButtonMotion {
  const MistakeMapButton({
    required super.child,
    required super.onPressed,
    super.key,
    super.onLongPress,
    super.onTapDown,
    super.onTapUp,
    super.focusNode,
    super.autofocus,
    super.style,
    super.focusable,
  });
}

class MistakeMapFilledButton extends FilledButton with _MistakeMapButtonMotion {
  const MistakeMapFilledButton({
    required super.child,
    required super.onPressed,
    super.key,
    super.onLongPress,
    super.onTapDown,
    super.onTapUp,
    super.focusNode,
    super.autofocus,
    super.style,
    super.focusable,
  });
}

class MistakeMapOutlinedButton extends OutlinedButton
    with _MistakeMapButtonMotion {
  const MistakeMapOutlinedButton({
    required super.child,
    required super.onPressed,
    super.key,
    super.onLongPress,
    super.onTapDown,
    super.onTapUp,
    super.focusNode,
    super.autofocus,
    super.style,
    super.focusable,
  });
}

class MistakeMapIconButton extends IconButton with _MistakeMapButtonMotion {
  const MistakeMapIconButton({
    required super.icon,
    required super.onPressed,
    super.key,
    super.onLongPress,
    super.onTapDown,
    super.onTapUp,
    super.focusNode,
    super.autofocus,
    super.style,
    super.focusable,
    super.iconButtonMode,
  });
}

class MistakeMapHyperlinkButton extends HyperlinkButton
    with _MistakeMapButtonMotion {
  const MistakeMapHyperlinkButton({
    required super.child,
    required super.onPressed,
    super.key,
    super.onLongPress,
    super.onTapDown,
    super.onTapUp,
    super.focusNode,
    super.autofocus,
    super.style,
    super.focusable,
  });
}

class _MistakeMapButtonState extends State<BaseButton> {
  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final style = (widget as _MistakeMapButtonMotion).motionStyleOf(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : MistakeMapMotion.hover;
    return HoverButton(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onPressed: widget.onPressed,
      onLongPress: widget.onLongPress,
      focusEnabled: widget.focusable,
      onTapDown: widget.onTapDown,
      onTapUp: widget.onTapUp,
      builder: (context, states) {
        final disabled = states.contains(WidgetState.disabled);
        final rest = style.backgroundColor?.resolve({}) ?? Colors.transparent;
        final restingInk =
            style.textStyle?.resolve({})?.color ??
            style.foregroundColor?.resolve({}) ??
            MistakeMapDesign.content;
        final fill = disabled
            ? style.backgroundColor?.resolve(states) ?? rest
            : states.contains(WidgetState.pressed)
            ? const Color(0xFF194F90)
            : states.contains(WidgetState.hovered)
            ? MistakeMapDesign.primary
            : style.backgroundColor?.resolve(states) ?? rest;
        final shape =
            style.shape?.resolve(states) ?? const RoundedRectangleBorder();
        final padding = (style.padding?.resolve(states) ?? EdgeInsets.zero)
            .add(
              EdgeInsetsDirectional.symmetric(
                horizontal: theme.visualDensity.horizontal,
                vertical: theme.visualDensity.vertical,
              ),
            )
            .clamp(EdgeInsetsDirectional.zero, EdgeInsetsGeometry.infinity);
        return Semantics(
          container: true,
          button: true,
          enabled: widget.enabled,
          child: FocusBorder(
            focused: states.contains(WidgetState.focused),
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(begin: fill, end: fill),
              duration: duration,
              curve: MistakeMapMotion.hoverCurve,
              child: widget.child,
              builder: (context, color, child) {
                final background = color ?? fill;
                final ink = disabled
                    ? style.foregroundColor?.resolve(states) ?? restingInk
                    : MistakeMapDesign.hoverInk(
                        background,
                        restingInk,
                        restingFill: theme.scaffoldBackgroundColor,
                      );
                return PhysicalModel(
                  color: Colors.transparent,
                  shadowColor:
                      style.shadowColor?.resolve(states) ?? Colors.black,
                  elevation: style.elevation?.resolve(states) ?? 0,
                  borderRadius:
                      shape is RoundedRectangleBorder &&
                          shape.borderRadius is BorderRadius
                      ? shape.borderRadius as BorderRadius
                      : BorderRadius.zero,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: background,
                      shape: shape,
                    ),
                    child: Padding(
                      padding: padding,
                      child: IconTheme.merge(
                        data: IconThemeData(
                          color: ink,
                          size: style.iconSize?.resolve(states) ?? 14,
                        ),
                        child: DefaultTextStyle.merge(
                          style: theme.typography.body
                              ?.merge(style.textStyle?.resolve(states))
                              .copyWith(color: ink),
                          textAlign: TextAlign.center,
                          child: Center(
                            widthFactor: 1,
                            heightFactor: 1,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

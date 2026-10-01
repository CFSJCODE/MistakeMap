import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A LinkedIn link with a reserved footprint and a gentle expansion on hover.
/// Touch layouts show the name immediately; opening the profile always requires
/// a click, a tap, or keyboard activation.
class LinkedInProfileButton extends StatefulWidget {
  const LinkedInProfileButton({
    super.key,
    required this.name,
    required this.onPressed,
    this.focusNode,
  });

  final String name;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  State<LinkedInProfileButton> createState() => _LinkedInProfileButtonState();
}

class _LinkedInProfileButtonState extends State<LinkedInProfileButton>
    with SingleTickerProviderStateMixin {
  static const _rest = Color(0xFF075985);
  static const _expanded = Color(0xFF0369A1);
  static const _white = Color(0xFFFFFFFF);
  static const _tipWidth = 18.0;
  static const _labelStyle = TextStyle(
    color: _white,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _hovered = false;
  bool _focused = false;
  bool _touchLayout = false;
  bool _reduceMotion = false;
  bool _initialized = false;

  bool get _showName => _touchLayout || _hovered || _focused;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _touchLayout =
        media.size.shortestSide < 600 ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    _reduceMotion = media.disableAnimations;
    if (!_initialized || _reduceMotion || _touchLayout) {
      _controller.value = _showName ? 1 : 0;
    } else {
      _updateAnimation();
    }
    _initialized = true;
  }

  void _updateAnimation() {
    if (_reduceMotion) {
      _controller.value = _showName ? 1 : 0;
    } else if (_showName) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    _hovered = value;
    _updateAnimation();
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
    _updateAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = DefaultTextStyle.of(context).style.merge(_labelStyle);
    return LayoutBuilder(
      builder: (context, constraints) {
        final namePainter = TextPainter(
          text: TextSpan(text: widget.name, style: labelStyle),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 2,
          ellipsis: '…',
        )..layout();
        final desiredWidth = namePainter.width + 72;
        final footprintWidth = constraints.hasBoundedWidth
            ? math.min(desiredWidth + _tipWidth, constraints.maxWidth)
            : desiredWidth + _tipWidth;
        final tipWidth = math.min(
          _tipWidth,
          math.max(0.0, footprintWidth - 48),
        );
        final expandedWidth = math.max(0.0, footprintWidth - tipWidth);
        final collapsedWidth = math.min(48.0, expandedWidth);
        final labelWidth = math.max(0.0, expandedWidth - 72);
        namePainter.layout(maxWidth: labelWidth);
        final height = math.max(48.0, namePainter.height + 16);
        namePainter.dispose();

        return SizedBox(
          key: const ValueKey('linkedin-profile-footprint'),
          width: footprintWidth,
          height: height,
          child: Semantics(
            link: true,
            focusable: true,
            focused: _focused,
            label: 'LinkedIn de ${widget.name}',
            hint: 'Abre o perfil em uma nova aba ou no navegador',
            onTap: widget.onPressed,
            child: ExcludeSemantics(
              child: FocusableActionDetector(
                focusNode: widget.focusNode,
                onFocusChange: _setFocused,
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                },
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      widget.onPressed();
                      return null;
                    },
                  ),
                },
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final progress = Curves.easeInOutCubic.transform(
                      _controller.value,
                    );
                    final width =
                        collapsedWidth +
                        (expandedWidth - collapsedWidth) * progress;
                    final fill = Color.lerp(_rest, _expanded, progress)!;
                    final nameOpacity = const Interval(
                      0.68,
                      1,
                      curve: Curves.easeOutCubic,
                    ).transform(_controller.value);
                    return Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => _setHovered(true),
                        onExit: (_) => _setHovered(false),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          excludeFromSemantics: true,
                          onTap: widget.onPressed,
                          child: SizedBox(
                            width: width + tipWidth,
                            height: height,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                if (tipWidth > 0)
                                  Positioned(
                                    left: width - 12,
                                    top: (height - 24) / 2,
                                    child: Transform.rotate(
                                      angle: math.pi / 4,
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: fill,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                SizedBox(
                                  key: const ValueKey(
                                    'linkedin-profile-surface',
                                  ),
                                  width: width,
                                  height: height,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: fill,
                                      borderRadius: BorderRadius.circular(6),
                                      border: _focused
                                          ? Border.all(color: _white, width: 2)
                                          : null,
                                      boxShadow: _focused
                                          ? const [
                                              BoxShadow(
                                                color: Color(0xFF214572),
                                                spreadRadius: 2,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Stack(
                                        children: [
                                          Positioned(
                                            left: 8,
                                            top: (height - 32) / 2,
                                            child: const Icon(
                                              FluentIcons.linked_in_logo,
                                              color: _white,
                                              size: 32,
                                            ),
                                          ),
                                          Positioned(
                                            left: 48,
                                            top: 8,
                                            bottom: 8,
                                            child: Opacity(
                                              opacity: nameOpacity,
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 2,
                                                    height: 24,
                                                    color: _white,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  SizedBox(
                                                    width: labelWidth,
                                                    child: Transform(
                                                      alignment:
                                                          Alignment.centerLeft,
                                                      transform:
                                                          Matrix4.diagonal3Values(
                                                            nameOpacity,
                                                            1,
                                                            1,
                                                          ),
                                                      child: Text(
                                                        widget.name,
                                                        key: const ValueKey(
                                                          'linkedin-profile-label',
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: labelStyle,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

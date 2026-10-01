import 'package:flutter/widgets.dart';

abstract final class MistakeMapMotion {
  static const controls = Duration(milliseconds: 160);
  static const hover = Duration(milliseconds: 480);
  static const section = Duration(milliseconds: 180);
  static const page = Duration(milliseconds: 240);
  static const back = Duration(milliseconds: 180);
  static const curve = Curves.easeOutCubic;
  static const hoverCurve = Curves.easeInOutCubic;
}

/// Visits each destination once, retaining drafts and scroll on later visits.
class NavigationPages extends StatefulWidget {
  const NavigationPages({
    super.key,
    required this.index,
    required this.children,
    this.active = true,
  });

  final int index;
  final List<Widget> children;
  final bool active;

  @override
  State<NavigationPages> createState() => _NavigationPagesState();
}

class _NavigationPagesState extends State<NavigationPages> {
  late final Set<int> _visited = {widget.index};

  @override
  void didUpdateWidget(NavigationPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.index);
  }

  @override
  Widget build(BuildContext context) => PageEntrance(
    identity: widget.index,
    child: IndexedStack(
      index: widget.index,
      children: [
        for (var index = 0; index < widget.children.length; index++)
          if (_visited.contains(index))
            TickerMode(
              enabled: widget.active && index == widget.index,
              child: RepaintBoundary(child: widget.children[index]),
            )
          else
            const SizedBox.shrink(),
      ],
    ),
  );
}

/// Animates the cached page child, without rebuilding or scaling its content.
class MistakeMapPageRoute<T> extends PageRouteBuilder<T> {
  MistakeMapPageRoute({
    required BuildContext context,
    required WidgetBuilder builder,
    super.settings,
  }) : super(
         transitionDuration: MediaQuery.disableAnimationsOf(context)
             ? Duration.zero
             : MistakeMapMotion.page,
         reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
             ? Duration.zero
             : MistakeMapMotion.back,
         pageBuilder: (context, animation, secondaryAnimation) => Semantics(
           scopesRoute: true,
           explicitChildNodes: true,
           child: builder(context),
         ),
         transitionsBuilder: _transition,
       );

  static Widget _transition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final eased = MediaQuery.disableAnimationsOf(context)
        ? kAlwaysCompleteAnimation
        : animation.drive(CurveTween(curve: MistakeMapMotion.curve));
    return FadeTransition(
      opacity: eased,
      child: AnimatedBuilder(
        animation: eased,
        child: RepaintBoundary(child: child),
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 6 * (1 - eased.value)),
          child: child,
        ),
      ),
    );
  }
}

/// A single entrance for the selected tab; it keeps all page states intact.
class PageEntrance extends StatefulWidget {
  const PageEntrance({super.key, required this.identity, required this.child});
  final Object identity;
  final Widget child;

  @override
  State<PageEntrance> createState() => _PageEntranceState();
}

class _PageEntranceState extends State<PageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MistakeMapMotion.section,
    value: 1,
  );
  late final Animation<double> _eased = _controller.drive(
    CurveTween(curve: MistakeMapMotion.curve),
  );
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) _controller.value = 1;
  }

  @override
  void didUpdateWidget(PageEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity && !_reduced) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _eased.drive(Tween(begin: 0.985, end: 1.0)),
      child: AnimatedBuilder(
        animation: _eased,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 3 * (1 - _eased.value)),
          child: child,
        ),
      ),
    );
  }
}

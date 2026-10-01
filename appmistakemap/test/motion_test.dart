import 'package:appmistakemap/theme/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a rota reutiliza a página durante os quadros da transição', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext routeContext;
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) {
            routeContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    final route = MistakeMapPageRoute<void>(
      context: routeContext,
      builder: (_) {
        builds++;
        return const Center(child: Text('Página em movimento'));
      },
    );
    navigator.currentState!.push(route);
    await tester.pump();
    expect(builds, 1);
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      expect(builds, 1);
      expect(tester.takeException(), isNull);
    }
    expect(route.animation!.status, AnimationStatus.forward);
    await tester.pumpAndSettle();
    expect(route.animation!.status, AnimationStatus.completed);
    expect(builds, 1);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(builds, 1);
  });

  testWidgets('movimento reduzido conclui push e pop sem avançar o relógio', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext routeContext;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            routeContext = context;
            return const Center(child: Text('Página inicial'));
          },
        ),
      ),
    );
    final route = MistakeMapPageRoute<String>(
      context: routeContext,
      builder: (_) => const Center(child: Text('Página sem movimento')),
    );
    final result = navigator.currentState!.push(route);
    await tester.pump();
    await tester.pump();
    expect(route.animation!.status, AnimationStatus.completed);
    expect(find.text('Página sem movimento'), findsOneWidget);
    navigator.currentState!.pop('concluído');
    await tester.pump();
    await tester.pump();
    expect(await result, 'concluído');
    expect(find.text('Página sem movimento'), findsNothing);
    expect(find.text('Página inicial'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trocas rápidas preservam o estado da página durante a entrada', (
    tester,
  ) async {
    final harness = GlobalKey<_EntranceHarnessState>();
    const counter = ValueKey('counter');
    await tester.pumpWidget(_EntranceHarness(key: harness, counter: counter));
    final originalState = tester.state<_CounterState>(find.byKey(counter));
    await tester.tap(find.text('Contador: 0'));
    await tester.pump();
    expect(find.text('Contador: 1'), findsOneWidget);
    for (var navigation = 0; navigation < 6; navigation++) {
      await tester.tap(find.text('Próxima seção'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.state<_CounterState>(find.byKey(counter)),
        same(originalState),
      );
      expect(find.text('Contador: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    final entrance = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(PageEntrance),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(entrance.opacity.value, 1);
    expect(
      tester.state<_CounterState>(find.byKey(counter)),
      same(originalState),
    );
  });

  testWidgets('reduzir movimento interrompe a entrada sem apagar o estado', (
    tester,
  ) async {
    final harness = GlobalKey<_EntranceHarnessState>();
    const counter = ValueKey('counter');
    await tester.pumpWidget(_EntranceHarness(key: harness, counter: counter));
    await tester.tap(find.text('Contador: 0'));
    await tester.pump();
    final originalState = tester.state<_CounterState>(find.byKey(counter));
    await tester.tap(find.text('Próxima seção'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final opacity = tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(PageEntrance),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity;
    expect(opacity.value, lessThan(1));
    harness.currentState!.reduceMotion();
    await tester.pump();
    expect(opacity.status, AnimationStatus.completed);
    expect(
      tester.state<_CounterState>(find.byKey(counter)),
      same(originalState),
    );
    expect(find.text('Contador: 1'), findsOneWidget);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.tap(find.text('Próxima seção'));
    await tester.pump();
    expect(
      tester.state<_CounterState>(find.byKey(counter)),
      same(originalState),
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'destinos iniciam na primeira visita e retêm o rascunho ao voltar',
    (tester) async {
      final observations = _PageObservations();
      await tester.pumpWidget(_NavigationHarness(observations: observations));
      expect(observations.created, [0]);
      final originalPage = tester.state<_DraftPageState>(
        find.byKey(const ValueKey('draft-0')),
      );
      await tester.enterText(find.byType(TextField), 'Meu rascunho preservado');
      await tester.tap(find.text('Seção 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(observations.created, [0, 1]);
      expect(observations.disposed, isEmpty);
      await tester.tap(find.text('Seção 0'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(observations.created, [0, 1]);
      expect(
        tester.state<_DraftPageState>(find.byKey(const ValueKey('draft-0'))),
        same(originalPage),
      );
      expect(find.text('Meu rascunho preservado'), findsOneWidget);
      expect(observations.disposed, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(observations.disposed, containsAll([0, 1]));
    },
  );

  testWidgets('tickers param nas páginas ocultas e quando a navegação pausa', (
    tester,
  ) async {
    final observations = _PageObservations();
    await tester.pumpWidget(_NavigationHarness(observations: observations));
    await tester.pump(const Duration(milliseconds: 40));
    expect(observations.ticks[0], greaterThan(0));
    await tester.tap(find.text('Seção 1'));
    await tester.pump();
    final hiddenTicks = observations.ticks[0];
    await tester.pump(const Duration(milliseconds: 250));
    expect(observations.ticks[0], hiddenTicks);
    expect(observations.ticks[1], greaterThan(0));
    await tester.tap(find.text('Pausar navegação'));
    await tester.pump();
    final pausedTicks = observations.ticks[1];
    await tester.pump(const Duration(seconds: 1));
    expect(observations.ticks[0], hiddenTicks);
    expect(observations.ticks[1], pausedTicks);
    await tester.tap(find.text('Retomar navegação'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(observations.ticks[1], greaterThan(pausedTicks!));
    expect(observations.ticks[0], hiddenTicks);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _EntranceHarness extends StatefulWidget {
  const _EntranceHarness({super.key, required this.counter});
  final Key counter;

  @override
  State<_EntranceHarness> createState() => _EntranceHarnessState();
}

class _EntranceHarnessState extends State<_EntranceHarness> {
  var identity = 0;
  var reduced = false;

  void reduceMotion() => setState(() => reduced = true);

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => identity++),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Próxima seção'),
            ),
          ),
          Expanded(
            child: PageEntrance(
              identity: identity,
              child: _Counter(key: widget.counter),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var count = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: GestureDetector(
      onTap: () => setState(() => count++),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Contador: $count'),
      ),
    ),
  );
}

class _PageObservations {
  final List<int> created = [];
  final List<int> disposed = [];
  final Map<int, int> ticks = {};
}

class _NavigationHarness extends StatefulWidget {
  const _NavigationHarness({required this.observations});
  final _PageObservations observations;

  @override
  State<_NavigationHarness> createState() => _NavigationHarnessState();
}

class _NavigationHarnessState extends State<_NavigationHarness> {
  var index = 0;
  var active = true;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          Row(
            children: [
              for (var destination = 0; destination < 3; destination++)
                GestureDetector(
                  onTap: () => setState(() => index = destination),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Seção $destination'),
                  ),
                ),
              GestureDetector(
                onTap: () => setState(() => active = !active),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    active ? 'Pausar navegação' : 'Retomar navegação',
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: NavigationPages(
              index: index,
              active: active,
              children: [
                for (var page = 0; page < 3; page++)
                  _DraftPage(
                    key: ValueKey('draft-$page'),
                    index: page,
                    observations: widget.observations,
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DraftPage extends StatefulWidget {
  const _DraftPage({
    super.key,
    required this.index,
    required this.observations,
  });
  final int index;
  final _PageObservations observations;

  @override
  State<_DraftPage> createState() => _DraftPageState();
}

class _DraftPageState extends State<_DraftPage>
    with SingleTickerProviderStateMixin {
  final draft = TextEditingController();
  late final AnimationController animation;

  @override
  void initState() {
    super.initState();
    widget.observations.created.add(widget.index);
    widget.observations.ticks[widget.index] = 0;
    animation =
        AnimationController(
          vsync: this,
          duration: const Duration(seconds: 1),
        )..addListener(() {
          widget.observations.ticks.update(widget.index, (ticks) => ticks + 1);
        });
    animation.repeat(reverse: true);
  }

  @override
  void dispose() {
    widget.observations.disposed.add(widget.index);
    draft.dispose();
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: TextField(controller: draft),
  );
}

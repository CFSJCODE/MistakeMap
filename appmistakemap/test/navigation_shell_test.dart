import 'package:appmistakemap/layout/navigation_shell.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 320 e 390: barra inferior; 768: trilho compacto (tablet em pé); 1280:
  // trilho largo.
  for (final scenario in [
    (320.0, 2.0),
    (390.0, 1.0),
    (768.0, 1.0),
    (1280.0, 1.0),
  ]) {
    testWidgets('Navegação em ${scenario.$1}px com fonte ${scenario.$2}x', (
      tester,
    ) async {
      tester.view.physicalSize = Size(scenario.$1, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      var about = 0;
      await tester.pumpWidget(
        FluentApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scenario.$2)),
            child: child!,
          ),
          home: StatefulBuilder(
            builder: (context, setState) => AppNavigationShell(
              selectedIndex: selected,
              onSelected: (index) => setState(() => selected = index),
              hasAdmin: true,
              onAbout: () => about++,
              child: const ColoredBox(
                color: Colors.white,
                child: Center(child: Text('Conteúdo da seção')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(ValueKey('navigation-$i')));
        await tester.pumpAndSettle();
        expect(selected, i);
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(ValueKey('navigation-$i'))).height,
          greaterThanOrEqualTo(44),
        );
      }
      final effective = scenario.$1 / scenario.$2;
      // Na barra do celular (360 a 600 px efetivos), Sobre é uma fatia
      // própria; abaixo de 360 px e nos trilhos ele mora no Mais.
      final aboutInBar = effective >= 360 && effective < 600;
      if (scenario.$1 < 840) {
        await tester.tap(find.byKey(const ValueKey('navigation-more')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Admin'));
        await tester.pumpAndSettle();
        expect(selected, 4);
        if (!aboutInBar) {
          await tester.tap(find.byKey(const ValueKey('navigation-more')));
          await tester.pumpAndSettle();
        }
      } else {
        await tester.tap(find.byKey(const ValueKey('navigation-4')));
        await tester.pumpAndSettle();
        expect(selected, 4);
      }
      if (aboutInBar) {
        await tester.tap(find.byKey(const ValueKey('navigation-about')));
      } else {
        await tester.tap(find.text('Sobre o App'));
      }
      await tester.pumpAndSettle();
      expect(about, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Aluno não recebe destino de administração', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        home: AppNavigationShell(
          selectedIndex: 0,
          onSelected: (_) {},
          onAbout: () {},
          hasAdmin: false,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('navigation-more')));
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsNothing);
    // Janela padrão de 800 px: trilho compacto, onde Sobre mora no Mais.
    expect(find.text('Sobre o App'), findsOneWidget);
  });

  for (final width in [390.0, 768.0, 1280.0]) {
    testWidgets('Estudar e Sair ficam à vista em ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var study = 0;
      var signOut = 0;
      await tester.pumpWidget(
        FluentApp(
          home: AppNavigationShell(
            selectedIndex: 0,
            onSelected: (_) {},
            onAbout: () {},
            onStudy: () => study++,
            onSignOut: () => signOut++,
            hasAdmin: false,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> abrirMais() async {
        if (width >= 840) return;
        await tester.tap(find.byKey(const ValueKey('navigation-more')));
        await tester.pumpAndSettle();
      }

      if (width < 600) {
        // Fatia própria da barra do celular.
        await tester.tap(find.byKey(const ValueKey('navigation-study')));
      } else {
        await abrirMais();
        await tester.tap(find.text('Estudar com a IA'));
      }
      await tester.pumpAndSettle();
      expect(study, 1);
      await abrirMais();
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();
      expect(signOut, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Mapa é uma aba e tocar na aba atual avisa de novo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var taps = 0;
    var selected = 0;
    await tester.pumpWidget(
      FluentApp(
        home: StatefulBuilder(
          builder: (context, setState) => AppNavigationShell(
            selectedIndex: selected,
            onSelected: (index) {
              taps++;
              setState(() => selected = index);
            },
            onAbout: () {},
            hasAdmin: false,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Novo'), findsNothing);
    expect(find.text('Analisar com IA'), findsNothing);
    // O Mapa troca de aba como as demais: a barra continua à vista.
    await tester.tap(find.byKey(const ValueKey('navigation-2')));
    await tester.pumpAndSettle();
    expect(selected, 2);
    // Tocar de novo na aba atual avisa outra vez, para a página voltar à raiz.
    await tester.tap(find.byKey(const ValueKey('navigation-2')));
    await tester.pumpAndSettle();
    expect(taps, 2);
    await tester.tap(find.text('Caderno'));
    await tester.pumpAndSettle();
    expect(selected, 3);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 768.0, 1280.0]) {
    testWidgets('Analisar fica à vista em ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var analysis = 0;
      await tester.pumpWidget(
        FluentApp(
          home: AppNavigationShell(
            selectedIndex: 0,
            onSelected: (_) {},
            onAbout: () {},
            onAnalysis: () => analysis++,
            hasAdmin: false,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('navigation-action'));
      expect(action, findsOneWidget);
      // Alvo de toque do Material (48) e do Fluent (40) em qualquer largura.
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(analysis, 1);
      expect(tester.takeException(), isNull);
    });
  }
  for (final reduced in [false, true]) {
    testWidgets('Hover rápido mantém botões e rótulos estáveis '
        '(movimento reduzido: $reduced)', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      var actions = 0;
      await tester.pumpWidget(
        FluentApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: StatefulBuilder(
            builder: (context, setState) => AppNavigationShell(
              selectedIndex: selected,
              onSelected: (index) {
                actions++;
                setState(() => selected = index);
              },
              hasAdmin: true,
              onAbout: () => actions++,
              child: const Center(child: Text('Conteúdo preservado')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final labels = <int, String>{
        0: 'Início',
        1: 'Meus exercícios',
        3: 'Caderno de erros',
        2: 'Mapa de erros',
        4: 'Administração',
        6: 'Sobre o App',
      };
      final buttons = <int, Finder>{
        for (final index in [0, 1, 2, 3, 4])
          index: find.byKey(ValueKey('navigation-$index')),
        for (final index in [6])
          index: find
              .ancestor(
                of: find.text(labels[index]!),
                matching: find.byType(Button),
              )
              .first,
      };
      final originalButtons = {
        for (final entry in buttons.entries)
          entry.key: tester.getRect(entry.value),
      };
      final originalLabels = {
        for (final entry in labels.entries)
          entry.key: tester.getRect(find.text(entry.value)),
      };

      void verifyLayout() {
        for (final index in labels.keys) {
          final button = tester.getRect(buttons[index]!);
          final labelFinder = find.text(labels[index]!);
          expect(labelFinder, findsOneWidget);
          final label = tester.getRect(labelFinder);
          _expectSameRect(button, originalButtons[index]!);
          _expectSameRect(label, originalLabels[index]!);
          expect(button.height, greaterThanOrEqualTo(44));
          expect(label.height, greaterThan(0));
          expect(button.inflate(.01).contains(label.topLeft), isTrue);
          expect(button.inflate(.01).contains(label.bottomRight), isTrue);
        }
        expect(selected, 0);
        expect(actions, 0);
        expect(find.text('Conteúdo preservado'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1000, 800));
      addTearDown(mouse.removePointer);
      for (var pass = 0; pass < 2; pass++) {
        for (final index in [0, 1, 3, 2, 4, 6, 4, 2, 3, 1, 0]) {
          await mouse.moveTo(tester.getCenter(buttons[index]!));
          await tester.pump(const Duration(milliseconds: 16));
          verifyLayout();
        }
      }
      if (reduced) {
        // A zero-duration hover must finish without an extra animation frame.
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      await mouse.moveTo(const Offset(1000, 800));
      await tester.pumpAndSettle();
      verifyLayout();
    });
  }
}

void _expectSameRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, .01));
  expect(actual.top, closeTo(expected.top, .01));
  expect(actual.width, closeTo(expected.width, .01));
  expect(actual.height, closeTo(expected.height, .01));
}

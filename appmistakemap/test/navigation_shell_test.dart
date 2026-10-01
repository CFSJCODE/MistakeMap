import 'package:appmistakemap/layout/navigation_shell.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [(320.0, 2.0), (390.0, 1.0), (1280.0, 1.0)]) {
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
      if (scenario.$1 < 840) {
        await tester.tap(find.byKey(const ValueKey('navigation-more')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Admin'));
        await tester.pumpAndSettle();
        expect(selected, 4);
        await tester.tap(find.byKey(const ValueKey('navigation-more')));
        await tester.pumpAndSettle();
      } else {
        await tester.tap(find.byKey(const ValueKey('navigation-4')));
        await tester.pumpAndSettle();
        expect(selected, 4);
      }
      await tester.tap(find.text('Sobre o App'));
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
    expect(find.text('Sobre o App'), findsOneWidget);
  });

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
              onAnalysis: () => actions++,
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
        3: 'Novo exercício',
        5: 'Analisar com IA',
        2: 'Mapa de erros',
        4: 'Administração',
        6: 'Sobre o App',
      };
      final buttons = <int, Finder>{
        for (final index in [0, 1, 2, 3, 4])
          index: find.byKey(ValueKey('navigation-$index')),
        for (final index in [5, 6])
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
        for (final index in [0, 1, 3, 5, 2, 4, 6, 4, 2, 5, 3, 1, 0]) {
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

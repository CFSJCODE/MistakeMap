import 'package:appmistakemap/ai/material_control_styles.dart';
import 'package:appmistakemap/main.dart' show temaFluent;
import 'package:appmistakemap/theme/control_styles.dart';
import 'package:appmistakemap/theme/design_tokens.dart';
import 'package:appmistakemap/theme/motion.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _controlKey = ValueKey('hover-control');

double _contrast(Color ink, Color fill) {
  final a = ink.computeLuminance();
  final b = fill.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

Color _fluentFill(WidgetTester tester) {
  final paint = find.descendant(
    of: find.byKey(_controlKey),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox && widget.decoration is ShapeDecoration,
    ),
  );
  return (tester.widget<DecoratedBox>(paint.first).decoration
          as ShapeDecoration)
      .color!;
}

Color _materialFill(WidgetTester tester) {
  final paint = find.descendant(
    of: find.byKey(_controlKey),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color != null,
    ),
  );
  return (tester.widget<DecoratedBox>(paint.first).decoration as BoxDecoration)
      .color!;
}

void _expectReadable(WidgetTester tester, Color fill) {
  final label = find.text('Ação');
  if (label.evaluate().isNotEmpty) {
    final ink = DefaultTextStyle.of(tester.element(label)).style.color!;
    expect(_contrast(ink, fill), greaterThanOrEqualTo(4.5));
  }
  final icon = find.byIcon(fluent.WindowsIcons.add);
  final ink = IconTheme.of(tester.element(icon)).color!;
  expect(_contrast(ink, fill), greaterThanOrEqualTo(4.5));
}

void main() {
  setUp(() {
    final strategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
  });
  final fluentButtons = <String, Widget Function(VoidCallback?)>{
    'FilledButton': (action) => MistakeMapFilledButton(
      key: _controlKey,
      onPressed: action,
      style: MistakeMapControls.button(
        background: MistakeMapDesign.navy,
        foreground: const Color(0xFFFFFFFF),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(fluent.WindowsIcons.add),
          SizedBox(width: 8),
          Text('Ação'),
        ],
      ),
    ),
    'Button': (action) => MistakeMapButton(
      key: _controlKey,
      onPressed: action,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(fluent.WindowsIcons.add),
          SizedBox(width: 8),
          Text('Ação'),
        ],
      ),
    ),
    'OutlinedButton': (action) => MistakeMapOutlinedButton(
      key: _controlKey,
      onPressed: action,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(fluent.WindowsIcons.add),
          SizedBox(width: 8),
          Text('Ação'),
        ],
      ),
    ),
    'HyperlinkButton': (action) => MistakeMapHyperlinkButton(
      key: _controlKey,
      onPressed: action,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(fluent.WindowsIcons.add),
          SizedBox(width: 8),
          Text('Ação'),
        ],
      ),
    ),
    'IconButton': (action) => MistakeMapIconButton(
      key: _controlKey,
      onPressed: action,
      icon: const Icon(fluent.WindowsIcons.add),
    ),
  };

  for (final entry in fluentButtons.entries) {
    testWidgets(
      'Fluent ${entry.key}: cores intermediárias, contraste e retorno',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          fluent.FluentApp(
            theme: temaFluent,
            home: Center(child: entry.value(() => calls++)),
          ),
        );
        await tester.pumpAndSettle();
        final bounds = tester.getRect(find.byKey(_controlKey));
        final base = _fluentFill(tester);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1, 1));
        addTearDown(mouse.removePointer);
        await mouse.moveTo(bounds.center);
        await tester.pump();
        expect(
          tester
              .widget<fluent.HoverButtonInherited>(
                find.descendant(
                  of: find.byKey(_controlKey),
                  matching: find.byType(fluent.HoverButtonInherited),
                ),
              )
              .states,
          contains(WidgetState.hovered),
          reason: 'O ponteiro está no centro do botão: $bounds',
        );
        expect(_fluentFill(tester), base);
        await tester.pump(const Duration(milliseconds: 40));
        expect(_fluentFill(tester), isNot(base));
        expect(_fluentFill(tester), isNot(MistakeMapDesign.primary));
        for (var step = 0; step < 22; step++) {
          _expectReadable(
            tester,
            Color.alphaBlend(_fluentFill(tester), MistakeMapDesign.background),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(_fluentFill(tester), MistakeMapDesign.primary);
        expect(tester.getRect(find.byKey(_controlKey)), bounds);
        expect(calls, 0);
        await mouse.moveTo(const Offset(1, 1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 65));
        expect(_fluentFill(tester), isNot(base));
        await tester.pumpAndSettle();
        expect(_fluentFill(tester), base);
        await tester.tap(find.byKey(_controlKey));
        expect(calls, 1);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final reduced in [false, true]) {
    testWidgets('Fluent desativado e movimento reduzido: $reduced', (
      tester,
    ) async {
      Widget app(VoidCallback? action) => fluent.FluentApp(
        theme: temaFluent,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: Center(child: fluentButtons['Button']!(action)),
      );
      await tester.pumpWidget(app(null));
      await tester.pumpAndSettle();
      final disabled = _fluentFill(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(_controlKey)));
      await tester.pumpAndSettle();
      expect(_fluentFill(tester), disabled);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpWidget(app(() {}));
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(find.byKey(_controlKey)));
      await tester.pump();
      if (reduced) {
        expect(_fluentFill(tester), MistakeMapDesign.primary);
      } else {
        expect(_fluentFill(tester), isNot(MistakeMapDesign.primary));
        await tester.pump(MistakeMapMotion.hover);
        expect(_fluentFill(tester), MistakeMapDesign.primary);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final variant in ['outlined', 'text', 'icon', 'filled']) {
    testWidgets('Material $variant: transição real e contraste', (
      tester,
    ) async {
      await tester.pumpWidget(
        material.MaterialApp(
          home: material.Scaffold(
            body: Builder(
              builder: (context) {
                final style = MistakeMapMaterialControls.button(context);
                const child = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(fluent.WindowsIcons.add),
                    SizedBox(width: 8),
                    Text('Ação'),
                  ],
                );
                final button = switch (variant) {
                  'text' => material.TextButton(
                    key: _controlKey,
                    style: style,
                    onPressed: () {},
                    child: child,
                  ),
                  'icon' => material.IconButton(
                    key: _controlKey,
                    style: style,
                    onPressed: () {},
                    icon: const Icon(fluent.WindowsIcons.add),
                  ),
                  'filled' => material.FilledButton(
                    key: _controlKey,
                    style: style,
                    onPressed: () {},
                    child: child,
                  ),
                  _ => material.OutlinedButton(
                    key: _controlKey,
                    style: style,
                    onPressed: () {},
                    child: child,
                  ),
                };
                return Center(child: button);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final base = _materialFill(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(_controlKey)));
      await tester.pump();
      expect(_materialFill(tester), base);
      await tester.pump(const Duration(milliseconds: 40));
      expect(_materialFill(tester), isNot(base));
      expect(_materialFill(tester), isNot(MistakeMapDesign.primary));
      for (var step = 0; step < 22; step++) {
        _expectReadable(tester, _materialFill(tester));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(_materialFill(tester), MistakeMapDesign.primary);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(_materialFill(tester), base);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Fluent mantém foco de teclado, semântica e ação única', (
    tester,
  ) async {
    var calls = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      fluent.FluentApp(
        theme: temaFluent,
        home: Center(
          child: MistakeMapButton(
            key: _controlKey,
            focusNode: focus,
            onPressed: () => calls++,
            child: const Text('Ação'),
          ),
        ),
      ),
    );
    final semantics = tester.ensureSemantics();
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(
      tester.getSemantics(find.byKey(_controlKey)),
      matchesSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        isFocused: true,
        label: 'Ação',
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final reduced in [false, true]) {
    testWidgets('Material desativado e movimento reduzido: $reduced', (
      tester,
    ) async {
      Widget app(VoidCallback? action) => material.MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: material.Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: material.OutlinedButton(
                key: _controlKey,
                onPressed: action,
                style: MistakeMapMaterialControls.button(context),
                child: const Text('Ação'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(null));
      await tester.pumpAndSettle();
      final disabled = _materialFill(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(_controlKey)));
      await tester.pumpAndSettle();
      expect(_materialFill(tester), disabled);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpWidget(app(() {}));
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(find.byKey(_controlKey)));
      await tester.pump();
      if (reduced) {
        expect(_materialFill(tester), MistakeMapDesign.primary);
      } else {
        expect(_materialFill(tester), isNot(MistakeMapDesign.primary));
        await tester.pump(MistakeMapMotion.hover);
        expect(_materialFill(tester), MistakeMapDesign.primary);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

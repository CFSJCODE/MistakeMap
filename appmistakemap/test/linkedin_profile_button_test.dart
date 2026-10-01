import 'package:appmistakemap/about/linkedin_profile_button.dart';
import 'package:appmistakemap/main.dart' show temaFluent;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _name = 'Cláudio Francisco';
const _surface = ValueKey('linkedin-profile-surface');
const _label = ValueKey('linkedin-profile-label');

Future<void> _render(
  WidgetTester tester, {
  required VoidCallback onPressed,
  FocusNode? focusNode,
  Size size = const Size(900, 700),
  double scale = 1,
  bool disableAnimations = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    FluentApp(
      theme: temaFluent,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: Center(
        child: SizedBox(
          width: 256,
          child: LinkedInProfileButton(
            name: _name,
            onPressed: onPressed,
            focusNode: focusNode,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(1, 1));
  addTearDown(mouse.removePointer);
  return mouse;
}

double _width(WidgetTester tester) =>
    tester.getSize(find.byKey(_surface)).width;

void main() {
  testWidgets('Hover expande gradualmente e sai sem reiniciar a animação', (
    tester,
  ) async {
    await _render(tester, onPressed: () {});
    final closed = _width(tester);
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.byKey(_surface)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final intermediate = _width(tester);
    expect(intermediate, greaterThan(closed));

    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    expect(_width(tester), closeTo(intermediate, 0.1));
    await tester.pump(const Duration(milliseconds: 120));
    final reversing = _width(tester);
    expect(reversing, lessThan(intermediate));
    expect(reversing, greaterThan(closed));

    await mouse.moveTo(tester.getCenter(find.byKey(_surface)));
    await tester.pump();
    expect(_width(tester), closeTo(reversing, 0.1));
    await tester.pumpAndSettle();
    final expanded = _width(tester);
    expect(expanded, greaterThan(intermediate));
    expect(expanded, greaterThan(closed * 2));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Clique chama o destino uma vez sem exigir hover', (
    tester,
  ) async {
    var calls = 0;
    await _render(tester, onPressed: () => calls++);
    await tester.tap(find.byKey(_surface));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Foco revela o nome e Enter e Espaço ativam o destino', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var calls = 0;
    await _render(tester, focusNode: focus, onPressed: () => calls++);
    final closed = _width(tester);
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(_width(tester), greaterThan(closed));
    expect(find.text(_name), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(calls, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Semântica identifica o perfil e avisa a abertura externa', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _render(tester, onPressed: () {});
    final node = tester.getSemantics(
      find.bySemanticsLabel('LinkedIn de $_name'),
    );
    expect(node.getSemanticsData().label, 'LinkedIn de $_name');
    expect(node.getSemanticsData().hint, contains('nova aba'));
    expect(node.getSemanticsData().flagsCollection.isLink, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Preferência por movimento reduzido torna o hover imediato', (
    tester,
  ) async {
    await _render(tester, onPressed: () {}, disableAnimations: true);
    final closed = _width(tester);
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.byKey(_surface)));
    await tester.pump();
    await tester.pump();
    final expanded = _width(tester);
    expect(expanded, greaterThan(closed));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_width(tester), expanded);
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    await tester.pump();
    expect(_width(tester), closed);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('320px e texto 2x mostram o nome sem depender de hover', (
    tester,
  ) async {
    var calls = 0;
    await _render(
      tester,
      onPressed: () => calls++,
      size: const Size(320, 640),
      scale: 2,
    );
    expect(find.byKey(_label), findsOneWidget);
    expect(find.text(_name).hitTestable(), findsOneWidget);
    expect(_width(tester), lessThanOrEqualTo(256));
    expect(
      tester.getSize(find.byKey(_surface)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byKey(_surface));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

// Explicit preview generation only. Fixtures never enter the production app.
import 'dart:io';

import 'package:appmistakemap/ai/exercise_submission_view.dart';
import 'package:appmistakemap/ai/insights_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'analysis_test.dart' show FakeRepository, sample;

const generatePreviews = bool.fromEnvironment('GENERATE_PREVIEWS');

void main() {
  setUpAll(() async {
    if (!generatePreviews) return;
    final font = File('C:/Windows/Fonts/segoeui.ttf');
    if (await font.exists()) {
      await (FontLoader('PreviewUi')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
    final icons = File(
      'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (await icons.exists()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(await icons.readAsBytes())),
          ))
          .load();
    }
  });

  Widget preview(Widget child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      fontFamily: 'PreviewUi',
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: mapContentBlue),
      scaffoldBackgroundColor: mapBackground,
    ),
    home: RepaintBoundary(
      key: const Key('preview'),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.white,
            child: const Text(
              'PRÉVIA • DADOS SINTÉTICOS',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'PreviewUi',
                fontSize: 12,
                color: Colors.red,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    ),
  );

  testWidgets('preview charts and connections at 360px', (tester) async {
    tester.view.physicalSize = const Size(360, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeRepository()
      ..attempts = [
        sample(),
        sample(id: 'a2'),
        sample(id: 'a3', category: 'sinal', concept: 'Equações'),
        sample(id: 'a4', category: 'conceito', concept: 'Proporções'),
      ];
    await tester.pumpWidget(
      preview(ErrorMapView(userId: 'synthetic', repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const Key('preview')),
      matchesGoldenFile('previews/mapa-graficos-360.png'),
    );
    await tester.tap(find.text('Conexões'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const Key('preview')),
      matchesGoldenFile('previews/mapa-conexoes-360.png'),
    );
  }, skip: !generatePreviews);

  testWidgets('preview submission at 360px', (tester) async {
    tester.view.physicalSize = const Size(360, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      preview(
        ExerciseSubmissionView(
          userId: 'synthetic',
          repository: FakeRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const Key('preview')),
      matchesGoldenFile('previews/formulario-360.png'),
    );
  }, skip: !generatePreviews);
}

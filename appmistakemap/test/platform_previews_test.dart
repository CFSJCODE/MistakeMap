import 'dart:io';
import 'dart:ui' as ui;

import 'package:appmistakemap/main.dart' show temaFluent;
import 'package:appmistakemap/platform/platform_hub.dart';
import 'package:appmistakemap/study/study_today_panel.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'platform_study_test.dart' show FakePlatform;

class _PreviewStore implements StudyStore {
  final _data = <String, String>{};
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }
}

void main() {
  testWidgets('prévias renderizadas com dados ilustrativos', (tester) async {
    await tester.runAsync(() async {
      final bytes = await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes();
      await (FontLoader(
        'Segoe UI',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      await (FontLoader('packages/fluent_ui/SegoeIcons')..addFont(
            rootBundle.load('packages/fluent_ui/fonts/SegoeIcons.ttf'),
          ))
          .load();
    });
    final repo = SupabaseStudyRepository.withTransport(
      (_, input) async => input['action'] == 'session'
          ? {'session': null}
          : {
              'profile': {
                'stage': 'superior',
                'daily_minutes': 15,
                'goal': 'Entender os circuitos de sensores',
              },
              'due_count': 4,
              'pending_diagnostics': 2,
              'estimated_minutes': 12,
              'reviewed_today': 3,
              'progress': {'reviews': 8, 'recall_rate': .75, 'period_days': 7},
            },
      store: _PreviewStore(),
    );
    for (final size in const [Size(390, 1100), Size(1280, 900)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      const key = Key('platform-preview');
      await tester.pumpWidget(
        FluentApp(
          theme: temaFluent.copyWith(
            typography: temaFluent.typography.apply(fontFamily: 'Segoe UI'),
          ),
          home: RepaintBoundary(
            key: key,
            child: size.width < 600
                ? ScaffoldPage(
                    content: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Prévia local · dados ilustrativos',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          StudyTodayPanel(
                            userId: 'preview',
                            repository: repo,
                            onExplore: () {},
                            onAnalyze: () {},
                            onStudy: () {},
                          ),
                        ],
                      ),
                    ),
                  )
                : PlatformHubPage(
                    userId: 'preview',
                    repository: FakePlatform(),
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final folder = Directory(
          '../_reversa_docs/platforma-estudos/screenshots',
        );
        await folder.create(recursive: true);
        await File(
          '${folder.path}/${size.width < 600 ? 'hoje-mobile' : 'biblioteca-desktop'}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }, skip: !const bool.fromEnvironment('GENERATE_PLATFORM_PREVIEWS'));
}

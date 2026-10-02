import 'package:appmistakemap/main.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

const _user = AppUser(
  id: '11111111-1111-4111-8111-111111111111',
  email: 'estudante@example.test',
  role: 'user',
);

// Canal usado pelo image_picker quando não há implementação nativa registrada.
const _canalImagePicker = MethodChannel('plugins.flutter.io/image_picker');

void main() {
  testWidgets('câmera indisponível mostra aviso em vez de falhar em silêncio', (
    tester,
  ) async {
    var chamadas = 0;
    final mensageiro = tester.binding.defaultBinaryMessenger;
    // Emulador sem câmera: o plugin responde com PlatformException.
    mensageiro.setMockMethodCallHandler(_canalImagePicker, (_) async {
      chamadas++;
      throw PlatformException(code: 'no_available_camera');
    });
    addTearDown(
      () => mensageiro.setMockMethodCallHandler(_canalImagePicker, null),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        theme: temaVidro,
        child: FluentApp(
          theme: temaFluent,
          home: const TelaAdicionarExercicio(user: _user),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final botao = find.text('Adicionar foto do exercício');
    await tester.ensureVisible(botao);
    await tester.tap(botao);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tirar uma foto'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(chamadas, 1);
    expect(
      find.text(
        'Não foi possível abrir a câmera. Escolha uma foto da galeria.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    // Deixa o aviso expirar para não sobrar timer pendente.
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });
}

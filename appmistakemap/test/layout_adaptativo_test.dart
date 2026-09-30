import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:appmistakemap/layout/adaptativo.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Monta [child] numa janela de [size] com escala de fonte e dobra simuladas.
Future<void> _render(
  WidgetTester tester,
  Widget child, {
  required Size size,
  double scale = 1,
  List<DisplayFeature> features = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(scale),
          displayFeatures: features,
        ),
        child: child,
      ),
    ),
  );
  // DoisPaineis mede a própria posição depois do primeiro quadro.
  await tester.pump();
}

DisplayFeature _dobradica(Rect bounds) => DisplayFeature(
  bounds: bounds,
  type: DisplayFeatureType.hinge,
  state: DisplayFeatureState.postureFlat,
);

DisplayFeature _dobra(Rect bounds, DisplayFeatureState state) =>
    DisplayFeature(bounds: bounds, type: DisplayFeatureType.fold, state: state);

void main() {
  group('classes de largura (Material 3)', () {
    test('limites inferiores de cada classe', () {
      expect(InfoTela.classePara(0), ClasseLargura.compacta);
      expect(InfoTela.classePara(599.9), ClasseLargura.compacta);
      expect(InfoTela.classePara(600), ClasseLargura.media);
      expect(InfoTela.classePara(839.9), ClasseLargura.media);
      expect(InfoTela.classePara(840), ClasseLargura.expandida);
      expect(InfoTela.classePara(1199.9), ClasseLargura.expandida);
      expect(InfoTela.classePara(1200), ClasseLargura.grande);
      expect(InfoTela.classePara(1599.9), ClasseLargura.grande);
      expect(InfoTela.classePara(1600), ClasseLargura.extraGrande);
    });

    test('fonte ampliada reduz a largura efetiva', () {
      const tela = InfoTela(
        tamanho: Size(1440, 900),
        escalaTexto: 2,
        areaSegura: EdgeInsets.zero,
      );
      expect(tela.larguraEfetiva, 720);
      expect(tela.classe, ClasseLargura.media);
      expect(tela.pelomenos(ClasseLargura.media), isTrue);
      expect(tela.pelomenos(ClasseLargura.expandida), isFalse);
    });

    test('altura compacta: celular deitado ou metade de um Flip', () {
      const deitado = InfoTela(
        tamanho: Size(800, 360),
        escalaTexto: 1,
        areaSegura: EdgeInsets.zero,
      );
      expect(deitado.alturaCompacta, isTrue);
    });
  });

  group('dobras e dobradiças', () {
    test('dobradiça que oculta pixels separa a tela', () {
      final dobra = Dobra.de([
        _dobradica(const Rect.fromLTWH(540, 0, 34, 720)),
      ]);
      expect(dobra, isNotNull);
      expect(dobra!.eixo, Axis.vertical);
      expect(dobra.oculta, isTrue);
      expect(dobra.separa, isTrue);
    });

    test('dobra meio aberta separa; dobra plana e contínua não', () {
      final livro = Dobra.de([
        _dobra(
          const Rect.fromLTWH(0, 400, 700, 0),
          DisplayFeatureState.postureHalfOpened,
        ),
      ])!;
      expect(livro.eixo, Axis.horizontal);
      expect(livro.separa, isTrue);

      final plana = Dobra.de([
        _dobra(
          const Rect.fromLTWH(420, 0, 0, 900),
          DisplayFeatureState.postureFlat,
        ),
      ])!;
      expect(plana.separa, isFalse);
    });

    test('recortes de câmera não contam como dobra', () {
      expect(
        Dobra.de(const [
          DisplayFeature(
            bounds: Rect.fromLTWH(160, 0, 60, 30),
            type: DisplayFeatureType.cutout,
            state: DisplayFeatureState.unknown,
          ),
        ]),
        isNull,
      );
    });
  });

  group('LayoutAdaptativo (media queries em cascata)', () {
    Widget layout() => LayoutAdaptativo(
      compacta: (_) => const Text('compacta'),
      expandida: (_) => const Text('expandida'),
      extraGrande: (_) => const Text('extra'),
    );

    for (final (largura, esperado) in [
      (360.0, 'compacta'),
      (700.0, 'compacta'), // média não definida: cai para compacta
      (900.0, 'expandida'),
      (1300.0, 'expandida'), // grande não definida: cai para expandida
      (1700.0, 'extra'),
    ]) {
      testWidgets('${largura.toInt()} px usa "$esperado"', (tester) async {
        await _render(tester, layout(), size: Size(largura, 800));
        expect(find.text(esperado), findsOneWidget);
      });
    }

    testWidgets('fonte 2x num desktop usa o layout de uma tela menor', (
      tester,
    ) async {
      await _render(tester, layout(), size: const Size(1700, 900), scale: 2);
      expect(find.text('expandida'), findsOneWidget);
    });
  });

  group('GradeAdaptativa (auto-fill)', () {
    test('colunas pelo espaço, respeitando o máximo', () {
      int colunas(double largura) => GradeAdaptativa.colunasPara(
        largura: largura,
        larguraMinimaItem: 160,
        espaco: 12,
        maxColunas: 4,
      );
      expect(colunas(288), 1);
      expect(colunas(340), 2);
      expect(colunas(700), 4);
      expect(colunas(3000), 4);
    });

    Future<List<double>> topos(WidgetTester tester, Size size) async {
      await _render(
        tester,
        GradeAdaptativa(
          larguraMinimaItem: 160,
          children: [for (var i = 0; i < 4; i++) Text('m$i')],
        ),
        size: size,
      );
      return [
        for (var i = 0; i < 4; i++) tester.getTopLeft(find.text('m$i')).dy,
      ];
    }

    testWidgets('4 colunas no desktop, empilhado no celular', (tester) async {
      final largo = await topos(tester, const Size(1280, 800));
      expect(largo.toSet(), hasLength(1));
      final estreito = await topos(tester, const Size(300, 800));
      expect(estreito.toSet(), hasLength(4));
    });
  });

  group('DoisPaineis', () {
    const inicio = ColoredBox(color: Color(0xFF000001), child: Text('inicio'));
    const fim = ColoredBox(color: Color(0xFF000002), child: Text('fim'));
    Widget paineis() => const DoisPaineis(inicio: inicio, fim: fim);

    testWidgets('celular sem dobra mostra só o painel inicial', (tester) async {
      await _render(tester, paineis(), size: const Size(390, 800));
      expect(find.text('inicio'), findsOneWidget);
      expect(find.text('fim'), findsNothing);
    });

    testWidgets('desktop mostra os dois painéis lado a lado', (tester) async {
      await _render(tester, paineis(), size: const Size(1280, 800));
      final a = tester.getRect(find.byWidget(inicio));
      final b = tester.getRect(find.byWidget(fim));
      expect(a.right, lessThan(b.left));
      expect(a.top, b.top);
    });

    testWidgets('tela dupla: nenhum painel fica sobre a dobradiça', (
      tester,
    ) async {
      // Duas telas de 360 px com dobradiça de 34 px (tipo Surface Duo):
      // largura total de classe "média", mas a dobra separa a tela.
      const hinge = Rect.fromLTWH(360, 0, 34, 720);
      await _render(
        tester,
        paineis(),
        size: const Size(754, 720),
        features: [_dobradica(hinge)],
      );
      final a = tester.getRect(find.byWidget(inicio));
      final b = tester.getRect(find.byWidget(fim));
      expect(a.right, lessThanOrEqualTo(hinge.left));
      expect(b.left, greaterThanOrEqualTo(hinge.right));
    });

    testWidgets(
      'dobrável em modo mesa: painel inicial em cima, final embaixo',
      (tester) async {
        // Z Flip/Fold meio aberto na horizontal.
        const dobra = Rect.fromLTWH(0, 420, 390, 0);
        await _render(
          tester,
          paineis(),
          size: const Size(390, 844),
          features: [_dobra(dobra, DisplayFeatureState.postureHalfOpened)],
        );
        final a = tester.getRect(find.byWidget(inicio));
        final b = tester.getRect(find.byWidget(fim));
        expect(a.bottom, lessThanOrEqualTo(dobra.top));
        expect(b.top, greaterThanOrEqualTo(dobra.bottom));
      },
    );
  });

  testWidgets('ForaDaDobra mantém a barra no painel esquerdo', (tester) async {
    const hinge = Rect.fromLTWH(360, 0, 34, 720);
    await _render(
      tester,
      const ForaDaDobra(child: SizedBox.expand(child: Text('abas'))),
      size: const Size(754, 720),
      features: [_dobradica(hinge)],
    );
    expect(
      tester.getRect(find.text('abas')).right,
      lessThanOrEqualTo(hinge.left),
    );
  });
}

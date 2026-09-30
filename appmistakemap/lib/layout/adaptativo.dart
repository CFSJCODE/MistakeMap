// Layout adaptativo: o equivalente de "media queries" do app.
//
// - Classes de largura de janela do Material 3 (compacta < 600, média < 840,
//   expandida < 1200, grande < 1600, extra grande). A largura é dividida pela
//   escala de fonte, então fonte ampliada num tablet recebe o layout de uma
//   tela menor em vez de espremer o conteúdo.
// - Dobráveis e telas duplas: a dobra ou dobradiça vem de
//   MediaQuery.displayFeaturesOf (Android: Galaxy Z Fold/Flip, Surface Duo e
//   similares). Uma dobradiça que oculta pixels, ou uma dobra meio aberta
//   (modo livro/mesa), separa a tela em dois painéis; nada é desenhado sobre ela.
// - Windows e macOS não informam a divisão física de notebooks com duas telas
//   (ASUS Zenbook/Zephyrus Duo): nesses, a janela é tratada pelo tamanho, como
//   qualquer outra. iPhone, iPad (Split View, Stage Manager) e Mac também se
//   adaptam pelo tamanho da janela e pelas áreas seguras.
import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';

/// Classes de largura de janela (Material 3 window size classes).
enum ClasseLargura { compacta, media, expandida, grande, extraGrande }

/// Limites inferiores de cada classe, em pixels lógicos por unidade de fonte.
abstract final class LimitesLargura {
  static const double media = 600;
  static const double expandida = 840;
  static const double grande = 1200;
  static const double extraGrande = 1600;
}

/// Abaixo desta altura efetiva a janela é "baixa": celular deitado, a metade
/// de cima de um Z Flip em modo mesa.
const double kAlturaCompacta = 480;

enum PosturaDobra { plana, meioAberta }

/// Dobra ou dobradiça informada pelo sistema, em coordenadas da janela.
@immutable
class Dobra {
  const Dobra({
    required this.area,
    required this.postura,
    required this.oculta,
  });

  /// Área da dobra. Largura zero numa dobra contínua (Z Fold); positiva numa
  /// dobradiça que oculta pixels (Surface Duo, duas telas lado a lado).
  final Rect area;
  final PosturaDobra postura;

  /// A dobradiça cobre pixels: conteúdo nunca deve atravessá-la.
  final bool oculta;

  /// Vertical quando a linha da dobra vai de cima a baixo (painéis à esquerda
  /// e à direita); horizontal quando divide em cima e embaixo.
  Axis get eixo => area.height >= area.width ? Axis.vertical : Axis.horizontal;

  /// A dobra divide a tela em duas áreas de uso: dobradiça que oculta pixels,
  /// ou dobra meio aberta. Uma dobra plana e contínua é tratada como uma tela só.
  bool get separa => oculta || postura == PosturaDobra.meioAberta;

  static Dobra? de(List<DisplayFeature> features) {
    for (final f in features) {
      if (f.type != DisplayFeatureType.fold &&
          f.type != DisplayFeatureType.hinge) {
        continue;
      }
      return Dobra(
        area: f.bounds,
        postura: f.state == DisplayFeatureState.postureHalfOpened
            ? PosturaDobra.meioAberta
            : PosturaDobra.plana,
        oculta:
            f.type == DisplayFeatureType.hinge &&
            f.bounds.width > 0 &&
            f.bounds.height > 0,
      );
    }
    return null;
  }
}

/// O que a janela oferece agora: tamanho, escala de fonte, classe, dobra e
/// áreas seguras.
@immutable
class InfoTela {
  const InfoTela({
    required this.tamanho,
    required this.escalaTexto,
    required this.areaSegura,
    this.dobra,
  });

  factory InfoTela.of(BuildContext context) {
    return InfoTela(
      tamanho: MediaQuery.sizeOf(context),
      escalaTexto: escalaDeTexto(context),
      areaSegura: MediaQuery.paddingOf(context),
      dobra: Dobra.de(MediaQuery.displayFeaturesOf(context)),
    );
  }

  final Size tamanho;
  final double escalaTexto;
  final EdgeInsets areaSegura;
  final Dobra? dobra;

  double get larguraEfetiva => tamanho.width / escalaTexto;
  ClasseLargura get classe => classePara(larguraEfetiva);
  bool get alturaCompacta => tamanho.height / escalaTexto < kAlturaCompacta;

  /// Há uma dobra que separa a tela em duas áreas de uso.
  bool get duasTelas => dobra?.separa ?? false;

  bool pelomenos(ClasseLargura minima) => classe.index >= minima.index;

  static ClasseLargura classePara(double larguraEfetiva) {
    if (larguraEfetiva >= LimitesLargura.extraGrande) {
      return ClasseLargura.extraGrande;
    }
    if (larguraEfetiva >= LimitesLargura.grande) return ClasseLargura.grande;
    if (larguraEfetiva >= LimitesLargura.expandida) {
      return ClasseLargura.expandida;
    }
    if (larguraEfetiva >= LimitesLargura.media) return ClasseLargura.media;
    return ClasseLargura.compacta;
  }

  /// Fator da escala de fonte medido no tamanho de corpo (14): também vale para
  /// escalas não lineares, como a do Android 14.
  static double escalaDeTexto(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) / 14;
}

/// Como uma sequência de @media (min-width): usa o construtor da maior classe
/// informada que não passa da classe atual. Mede o espaço do próprio widget
/// (como uma container query), não a janela inteira.
class LayoutAdaptativo extends StatelessWidget {
  const LayoutAdaptativo({
    super.key,
    required this.compacta,
    this.media,
    this.expandida,
    this.grande,
    this.extraGrande,
  });

  final WidgetBuilder compacta;
  final WidgetBuilder? media;
  final WidgetBuilder? expandida;
  final WidgetBuilder? grande;
  final WidgetBuilder? extraGrande;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final escala = InfoTela.escalaDeTexto(context);
        final largura = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final classe = InfoTela.classePara(largura / escala);
        final porClasse = [compacta, media, expandida, grande, extraGrande];
        for (var i = classe.index; i >= 0; i--) {
          final builder = porClasse[i];
          if (builder != null) return builder(context);
        }
        return compacta(context);
      },
    );
  }
}

/// Grade que escolhe o número de colunas pelo espaço disponível, como
/// `grid-template-columns: repeat(auto-fill, minmax(min, 1fr))`. A largura
/// mínima de cada item cresce com a escala de fonte.
class GradeAdaptativa extends StatelessWidget {
  const GradeAdaptativa({
    super.key,
    required this.children,
    this.larguraMinimaItem = 240,
    this.espaco = 12,
    this.maxColunas = 4,
  });

  final List<Widget> children;
  final double larguraMinimaItem;
  final double espaco;
  final int maxColunas;

  /// Quantas colunas cabem em [largura].
  static int colunasPara({
    required double largura,
    required double larguraMinimaItem,
    required double espaco,
    required int maxColunas,
  }) {
    final cabem = ((largura + espaco) / (larguraMinimaItem + espaco)).floor();
    return cabem.clamp(1, math.max(1, maxColunas));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final escala = InfoTela.escalaDeTexto(context);
        final colunas = colunasPara(
          largura: constraints.maxWidth,
          larguraMinimaItem: larguraMinimaItem * escala,
          espaco: espaco,
          maxColunas: maxColunas,
        );
        final larguraItem =
            (constraints.maxWidth - espaco * (colunas - 1)) / colunas;
        return Wrap(
          spacing: espaco,
          runSpacing: espaco,
          children: [
            for (final c in children) SizedBox(width: larguraItem, child: c),
          ],
        );
      },
    );
  }
}

/// Lista e detalhe (ou quaisquer dois conteúdos) lado a lado quando a tela
/// comporta, respeitando dobras e dobradiças; numa tela compacta sem dobra,
/// mostra só [inicio].
///
/// Com uma dobra vertical que separa a tela, cada painel fica de um lado da
/// dobra; com uma dobra horizontal (modo mesa), [inicio] fica em cima e [fim]
/// embaixo. A posição da dobra é medida contra a posição real do widget na
/// janela, então ele pode ficar abaixo de barras e margens.
class DoisPaineis extends StatefulWidget {
  const DoisPaineis({
    super.key,
    required this.inicio,
    required this.fim,
    this.proporcaoInicio = 0.4,
    this.espaco = 24,
  });

  final Widget inicio;
  final Widget fim;

  /// Fração da largura para [inicio] quando não há dobra que separe.
  final double proporcaoInicio;

  /// Espaço entre os painéis quando não há dobra que separe.
  final double espaco;

  /// A janela atual comporta dois painéis: classe expandida ou maior, ou uma
  /// dobra que separa a tela.
  static bool cabe(BuildContext context) {
    final tela = InfoTela.of(context);
    return tela.duasTelas || tela.pelomenos(ClasseLargura.expandida);
  }

  @override
  State<DoisPaineis> createState() => _DoisPaineisState();
}

class _DoisPaineisState extends State<DoisPaineis> {
  Rect? _naJanela;

  void _medir() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final area = box.localToGlobal(Offset.zero) & box.size;
    if (area != _naJanela) setState(() => _naJanela = area);
  }

  @override
  Widget build(BuildContext context) {
    final tela = InfoTela.of(context);
    if (!DoisPaineis.cabe(context)) return widget.inicio;
    WidgetsBinding.instance.addPostFrameCallback((_) => _medir());

    return LayoutBuilder(
      builder: (context, constraints) {
        final largura = constraints.maxWidth;
        final altura = constraints.maxHeight;
        final dobra = tela.dobra;
        final naJanela = _naJanela;
        if (dobra != null && dobra.separa && naJanela != null) {
          final local = dobra.area.shift(-naJanela.topLeft);
          if (dobra.eixo == Axis.vertical &&
              local.left > 0 &&
              local.right < largura) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: local.left, child: widget.inicio),
                SizedBox(width: local.width),
                SizedBox(width: largura - local.right, child: widget.fim),
              ],
            );
          }
          if (dobra.eixo == Axis.horizontal &&
              altura.isFinite &&
              local.top > 0 &&
              local.bottom < altura) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: local.top, child: widget.inicio),
                SizedBox(height: local.height),
                SizedBox(height: altura - local.bottom, child: widget.fim),
              ],
            );
          }
        }
        final larguraInicio =
            (largura - widget.espaco) * widget.proporcaoInicio;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: larguraInicio, child: widget.inicio),
            SizedBox(width: widget.espaco),
            Expanded(child: widget.fim),
          ],
        );
      },
    );
  }
}

/// Recuo que mantém [child] fora de uma dobradiça vertical: com a tela
/// separada em esquerda e direita, [child] fica só no painel da esquerda.
/// Usado na barra de abas, que não pode ter abas sobre a dobradiça.
class ForaDaDobra extends StatelessWidget {
  const ForaDaDobra({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tela = InfoTela.of(context);
    final dobra = tela.dobra;
    if (dobra == null || !dobra.separa || dobra.eixo != Axis.vertical) {
      return child;
    }
    final direita = tela.tamanho.width - dobra.area.left;
    if (direita <= 0 || direita >= tela.tamanho.width) return child;
    return Padding(
      padding: EdgeInsets.only(right: direita),
      child: child,
    );
  }
}

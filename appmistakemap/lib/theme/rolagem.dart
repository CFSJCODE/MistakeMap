import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

import 'design_tokens.dart';

/// Barra de rolagem do vidro, no navegador e no desktop: colada na borda
/// direita da janela (1 px de folga), sempre visível e mais grossa sob o
/// ponteiro. No celular nativo fica a rolagem do sistema, sem barra.
abstract final class BarraRolagem {
  /// Folga entre a barra e a borda da janela.
  static const margem = 1.0;

  /// Estilo da barra. [topo] é a altura que fica sob a barra superior de
  /// vidro: o trilho começa abaixo dela, para o polegar nunca ficar escondido.
  static ScrollbarThemeData estilo({double topo = 0}) {
    final recuo = EdgeInsets.only(top: topo + 4, bottom: 4);
    return ScrollbarThemeData(
      // Steel translúcido: legível sobre o fundo Aurora e sobre o vidro.
      scrollbarColor: const Color(0x8C4A5C6A),
      scrollbarPressingColor: MistakeMapDesign.steel,
      // Trilho de vidro claro, só com o ponteiro em cima e arrastando.
      backgroundColor: const Color(0xB3FFFFFF),
      trackBorderColor: const Color(0x00000000),
      hoveringTrackBorderColor: MistakeMapDesign.hairline,
      thickness: 6,
      hoveringThickness: 10,
      radius: const Radius.circular(100),
      hoveringRadius: const Radius.circular(100),
      crossAxisMargin: margem,
      hoveringCrossAxisMargin: margem,
      mainAxisMargin: 0,
      hoveringMainAxisMargin: 0,
      minThumbLength: 48,
      padding: recuo,
      hoveringPadding: recuo,
      expandContractAnimationDuration: const Duration(milliseconds: 120),
      contractDelay: const Duration(milliseconds: 250),
    );
  }

  /// A barra aparece no navegador (inclusive no celular) e no desktop.
  static bool visivel(BuildContext context) {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.macOS => true,
      _ => false,
    };
  }
}

/// Rolagem do app: cada lista vertical ganha a [BarraRolagem].
///
/// [topo] vale só para a rolagem de primeiro nível da página, que passa por
/// baixo da barra superior; listas aninhadas voltam ao recuo zero.
class RolagemVidro extends FluentScrollBehavior {
  const RolagemVidro({this.topo = 0});

  final double topo;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) != Axis.vertical ||
        !BarraRolagem.visivel(context)) {
      return child;
    }
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      style: BarraRolagem.estilo(topo: topo),
      child: topo == 0
          ? child
          : ScrollConfiguration(behavior: const RolagemVidro(), child: child),
    );
  }

  @override
  bool shouldNotify(RolagemVidro oldDelegate) => topo != oldDelegate.topo;
}

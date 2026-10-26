import 'package:flutter/painting.dart';

/// Obsidian Glass (modo claro): identidade visual compartilhada pelos fluxos
/// Fluent e Material. Fundo Pearl iluminado, vidro branco fosco, tinta escura
/// da paleta e acentos Aurora vivos onde a cor tem função.
abstract final class MistakeMapDesign {
  // ─── Paleta base (obrigatória) ────────────────────────────────────────────
  // No modo claro os tons escuros viram tinta e os claros, superfície.
  static const abyss = Color(0xFF06141B); // títulos e números
  static const deep = Color(0xFF11212D); // texto forte
  static const slate = Color(0xFF253745); // texto corrido
  static const steel = Color(0xFF4A5C6A); // texto secundário, ícones
  static const mist = Color(0xFF9BA8AB); // bordas fortes
  static const pearl = Color(0xFFCCD0CF); // base do fundo

  // ─── Superfícies derivadas ────────────────────────────────────────────────
  static const canvas = Color(0xFFEEF1F2); // Pearl clareado
  static const white = Color(0xFFFFFFFF);
  static const raised = white; // controle em repouso
  static const hover = Color(0xFFF1F4F5);
  static const pressed = Color(0xFFE6EBED);
  static const well = Color(0xFFF4F6F7); // áreas rebaixadas
  static const disabledFill = Color(0xFFE9EDEF);
  static const disabledInk = Color(0xFF6B7B83);
  static const hairline = Color(0x1411212D); // Deep 8%
  static const edge = Color(0x2411212D); // Deep 14%
  static const highlight = Color(0x3D11212D); // borda no hover
  static const fieldBorder = Color(0xFFC3CBCE);

  // ─── Acentos Aurora: cor só onde tem função ──────────────────────────────
  // Preenchimentos vivos: indicadores, ícones, gráficos e a ação principal.
  static const aqua = Color(0xFF36D6C3); // Início, foco, ação principal
  static const azure = Color(0xFF4C9DFF); // Lista, Cálculo
  static const violet = Color(0xFF9B7BFF); // Mapa e IA, Conceitual
  static const amber = Color(0xFFFFB547); // Caderno, Atenção
  static const mint = Color(0xFF4FD98B);
  static const coral = Color(0xFFFF6F7D);
  static const aurora = LinearGradient(colors: [aqua, azure, violet]);

  // Os mesmos acentos escurecidos, para texto e ícones (≥ 4,5:1 no branco).
  static const aquaInk = Color(0xFF08736A);
  static const azureInk = Color(0xFF1F5FBF);
  static const violetInk = Color(0xFF5532C9);
  static const amberInk = Color(0xFF8A5300);
  static const mintInk = Color(0xFF11744A);
  static const coralInk = Color(0xFFB42538);

  // Estados; sempre acompanhados de rótulo.
  static const ok = mintInk;
  static const warn = amberInk;
  static const bad = coralInk;
  static const ai = violetInk;

  // ─── Papéis usados pelas telas ────────────────────────────────────────────
  static const accent = aqua; // preenchimento do botão principal
  static const navy = abyss; // tinta mais escura e sombras
  static const primary = abyss; // títulos e item selecionado
  static const content = slate; // texto corrido
  static const strong = abyss;
  static const background = canvas;
  static const surface = white;
  static const border = edge;
  static const radius = 16.0;

  // Destaque vivo com texto branco legível em toda a faixa.
  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [aquaInk, azureInk, violetInk],
  );

  /// Vidro branco fosco: topo mais opaco, base deixando o fundo aparecer.
  static const glass = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xEBFFFFFF), Color(0xC7F7F9FA)],
  );

  /// Preenchimento de hover e pressão para um controle com este repouso.
  /// Um acento acende; as superfícies neutras escurecem um tom.
  static Color hoverFill(Color rest) => _accented(rest)
      ? Color.lerp(rest, white, .22)!
      : rest.a == 0
      ? const Color(0x0F11212D)
      : hover;

  static Color pressedFill(Color rest) => _accented(rest)
      ? Color.lerp(rest, abyss, .08)!
      : rest.a == 0
      ? const Color(0x1A11212D)
      : pressed;

  // Um preenchimento saturado (acento) e opaco, em vez de branco ou cinza.
  static bool _accented(Color color) {
    if (color.a < .5) return false;
    final hsl = HSLColor.fromColor(color);
    return hsl.saturation > .35 && hsl.lightness < .9;
  }

  /// Choose ink against the color actually painted during a hover transition.
  /// A direct ink tween loses contrast on the intermediate fill.
  static Color hoverInk(Color fill, Color restingInk, {Color? restingFill}) {
    final painted = Color.alphaBlend(fill, restingFill ?? canvas);
    double contrast(Color ink) {
      final a = ink.computeLuminance();
      final b = painted.computeLuminance();
      return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
    }

    if (contrast(restingInk) >= 4.5) return restingInk;
    // A paleta tem uma tinta clara e uma escura; vence a mais legível.
    return contrast(white) >= contrast(abyss) ? white : abyss;
  }
}

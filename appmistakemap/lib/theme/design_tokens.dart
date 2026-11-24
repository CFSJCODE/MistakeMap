import 'dart:ui' show ColorFilter, ImageFilter;

import 'package:flutter/painting.dart';
import 'package:flutter/animation.dart' show Curves;

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

  /// Ação principal: gradiente Aqua → Azure (artefatos Obsidian e Aurora).
  /// [primaryGradientFor] parte da cor animada do botão, para hover e
  /// pressão continuarem suaves.
  static LinearGradient primaryGradientFor(Color start) => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [start, Color.lerp(start, azure, .6)!],
  );
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

  // ─── Aurora Glass: hierarquia Fluent + vidro líquido ─────────────────────
  // L0 Mica: o fundo Aurora fixo. L1 Acrílico: cartões e painéis, quase
  // opacos para o texto. L2 Vidro líquido: só o que flutua (navegação, barras).

  /// Vidro branco fosco: topo mais opaco, base deixando o fundo aparecer.
  static const glass = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xEBFFFFFF), Color(0xC7F7F9FA)],
  );

  /// L1 Acrílico: branco 90→76%, legível sobre qualquer ponto do fundo.
  static const acrylic = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xE6FFFFFF), Color(0xC2F8FAFB)],
  );

  /// L2 Vidro líquido: mais transparente, com desfoque e saturação altos.
  static const liquid = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xB8FFFFFF), Color(0x75FFFFFF)],
  );

  /// Borda especular: a luz pega o topo e a base fica um tom mais escura.
  static const rim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xF2FFFFFF), Color(0x40FFFFFF), Color(0x2411212D)],
    stops: [0, .45, 1],
  );

  /// Reflexo a 145° (Fluent + Liquid Glass): a luz entra pelo canto superior
  /// esquerdo e some a 30% da superfície.
  static const glint = LinearGradient(
    begin: Alignment(-.57, -1),
    end: Alignment(.57, 1),
    colors: [Color(0xA6FFFFFF), Color(0x00FFFFFF)],
    stops: [0, .3],
  );

  /// Sombra interna da base: a aresta inferior do vidro escurece um tom.
  static const innerShade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0011212D), Color(0x1411212D)],
  );

  /// Saturação do que passa por trás do vidro, como no `saturate()` do CSS.
  static const glassSaturation = 1.3;

  /// Desfoque com saturação: o fundo atrás do vidro fica mais vivo, não
  /// acinzentado (o acrílico do Fluent e o vidro da Apple fazem o mesmo).
  static ImageFilter glassFilter(double sigma) => ImageFilter.compose(
    outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    inner: ColorFilter.matrix(_saturation(glassSaturation)),
  );

  // Matriz de saturação com os pesos de luminância do Rec. 709.
  static List<double> _saturation(double s) {
    const r = .2126, g = .7152, b = .0722;
    final i = 1 - s;
    return [
      r * i + s, g * i, b * i, 0, 0, //
      r * i, g * i + s, b * i, 0, 0, //
      r * i, g * i, b * i + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  static const acrylicBlur = 20.0;
  static const liquidBlur = 28.0;
  static const cardRadius = 20.0;

  /// Sombra do acrílico e a mais funda do vidro que flutua.
  static const acrylicShadow = [
    BoxShadow(
      color: Color(0x3811212D),
      blurRadius: 24,
      spreadRadius: -10,
      offset: Offset(0, 8),
    ),
  ];
  static const liquidShadow = [
    BoxShadow(
      color: Color(0x4D11212D),
      blurRadius: 40,
      spreadRadius: -14,
      offset: Offset(0, 18),
    ),
  ];

  /// Tom do acento no canto superior esquerdo de um cartão da seção.
  static RadialGradient tint(Color accent) => RadialGradient(
    center: Alignment.topLeft,
    radius: 1.2,
    colors: [accent.withValues(alpha: .30), accent.withValues(alpha: 0)],
    stops: const [0, .65],
  );

  /// Bloco de ícone preenchido: da tinta ao acento vivo, com glifo branco.
  static LinearGradient iconTile(Color ink, Color accent) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ink, Color.lerp(accent, ink, .2)!],
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

// ─── Escalas do design system (ver DESIGN_SYSTEM.md) ─────────────────────────
// Valores novos saem daqui, não de números soltos no widget.

/// Espaçamento em grade de 4 dp, com preferência pelos múltiplos de 8.
abstract final class Espaco {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  /// Recuo lateral das páginas no celular e acima de 600 px.
  static const pagina = md;
  static const paginaLarga = lg;

  /// Distância entre seções de uma página.
  static const secao = xl;

  /// Largura de leitura de uma coluna de conteúdo.
  static const larguraLeitura = 720.0;

  /// Alvo de toque mínimo (Material 48 dp; Apple 44 pt).
  static const alvoToque = 48.0;
}

/// Raios de canto. Controles pequenos têm raio menor que superfícies.
abstract final class Raio {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const pilula = 999.0;
}

/// Escala tipográfica do app (tamanhos em sp; a escala de texto do sistema
/// multiplica todos). Dois pesos de destaque só: 600 e 700.
abstract final class Tipo {
  static const tituloPagina = TextStyle(
    fontSize: 24,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: MistakeMapDesign.abyss,
  );
  static const tituloSecao = TextStyle(
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: MistakeMapDesign.abyss,
  );
  static const tituloComponente = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: MistakeMapDesign.abyss,
  );
  static const corpo = TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 15,
    height: 1.4,
    color: MistakeMapDesign.slate,
  );
  static const secundario = TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 13,
    height: 1.35,
    color: MistakeMapDesign.steel,
  );
  static const legenda = TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.3,
    color: MistakeMapDesign.steel,
  );

  /// Número de um indicador.
  static const numero = TextStyle(
    fontSize: 22,
    height: 1.15,
    fontWeight: FontWeight.w700,
    color: MistakeMapDesign.abyss,
  );

  /// Rótulo curto acima de um bloco ("PRÓXIMO PASSO").
  static const sobretitulo = TextStyle(
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: .6,
  );
}

/// Durações e curvas: 120 a 300 ms, nada mais longo em interação.
abstract final class Movimento {
  static const rapido = Duration(milliseconds: 120);
  static const padrao = Duration(milliseconds: 200);
  static const enfatico = Duration(milliseconds: 300);
  static const curva = Curves.easeOutCubic;
}

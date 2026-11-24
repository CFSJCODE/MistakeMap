import 'dart:ui' show Brightness, ColorFilter, ImageFilter;

import 'package:flutter/painting.dart';
import 'package:flutter/animation.dart' show Curves;

/// Obsidian Glass (modo claro): identidade visual compartilhada pelos fluxos
/// Fluent e Material. Fundo Pearl iluminado, vidro branco fosco, tinta escura
/// da paleta e acentos Aurora vivos onde a cor tem função.
/// Valores de uma aparência (clara ou escura) para os papéis de cor que mudam
/// com o tema. Os acentos Aurora vivos e o branco puro não mudam.
final class PaletaMistakeMap {
  const PaletaMistakeMap({
    required this.brightness,
    required this.abyss,
    required this.deep,
    required this.slate,
    required this.steel,
    required this.mist,
    required this.pearl,
    required this.canvas,
    required this.raised,
    required this.hover,
    required this.pressed,
    required this.well,
    required this.disabledFill,
    required this.disabledInk,
    required this.hairline,
    required this.edge,
    required this.highlight,
    required this.fieldBorder,
    required this.aquaInk,
    required this.azureInk,
    required this.violetInk,
    required this.amberInk,
    required this.mintInk,
    required this.coralInk,
    required this.glass,
    required this.acrylic,
    required this.liquid,
    required this.rim,
    required this.glint,
    required this.innerShade,
    required this.sombra,
    required this.veu,
  });

  final Brightness brightness;
  final Color abyss, deep, slate, steel, mist, pearl;
  final Color canvas, raised, hover, pressed, well, disabledFill, disabledInk;
  final Color hairline, edge, highlight, fieldBorder;
  final Color aquaInk, azureInk, violetInk, amberInk, mintInk, coralInk;
  final LinearGradient glass, acrylic, liquid, rim, glint, innerShade;

  /// Cor base das sombras (com alfa) e do véu atrás de diálogos.
  final Color sombra, veu;

  /// Obsidian Glass claro: a aparência publicada até aqui, valor a valor.
  static const claro = PaletaMistakeMap(
    brightness: Brightness.light,
    abyss: Color(0xFF06141B),
    deep: Color(0xFF11212D),
    slate: Color(0xFF253745),
    steel: Color(0xFF4A5C6A),
    mist: Color(0xFF9BA8AB),
    pearl: Color(0xFFCCD0CF),
    canvas: Color(0xFFEEF1F2),
    raised: Color(0xFFFFFFFF),
    hover: Color(0xFFF1F4F5),
    pressed: Color(0xFFE6EBED),
    well: Color(0xFFF4F6F7),
    disabledFill: Color(0xFFE9EDEF),
    disabledInk: Color(0xFF6B7B83),
    hairline: Color(0x1411212D),
    edge: Color(0x2411212D),
    highlight: Color(0x3D11212D),
    fieldBorder: Color(0xFFC3CBCE),
    aquaInk: Color(0xFF08736A),
    azureInk: Color(0xFF1F5FBF),
    violetInk: Color(0xFF5532C9),
    amberInk: Color(0xFF8A5300),
    mintInk: Color(0xFF11744A),
    coralInk: Color(0xFFB42538),
    glass: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xEBFFFFFF), Color(0xC7F7F9FA)],
    ),
    acrylic: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xE6FFFFFF), Color(0xC2F8FAFB)],
    ),
    liquid: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xB8FFFFFF), Color(0x75FFFFFF)],
    ),
    rim: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xF2FFFFFF), Color(0x40FFFFFF), Color(0x2411212D)],
      stops: [0, .45, 1],
    ),
    glint: LinearGradient(
      begin: Alignment(-.57, -1),
      end: Alignment(.57, 1),
      colors: [Color(0xA6FFFFFF), Color(0x00FFFFFF)],
      stops: [0, .3],
    ),
    innerShade: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x0011212D), Color(0x1411212D)],
    ),
    sombra: Color(0xFF11212D),
    veu: Color(0x6606141B),
  );

  /// Obsidian Glass escuro: o mesmo Obsidian como fundo, vidro grafite e as
  /// tintas dos acentos clareadas para manter ≥ 4,5:1 sobre a superfície.
  static const escuro = PaletaMistakeMap(
    brightness: Brightness.dark,
    abyss: Color(0xFFF1F5F7),
    deep: Color(0xFFE1E8EC),
    slate: Color(0xFFC9D3D9),
    steel: Color(0xFF9DADB6),
    mist: Color(0xFF5D6E79),
    pearl: Color(0xFF2B3944),
    canvas: Color(0xFF0B151B),
    raised: Color(0xFF1A262E),
    hover: Color(0xFF223039),
    pressed: Color(0xFF2A3943),
    well: Color(0xFF111C23),
    disabledFill: Color(0xFF1C2830),
    disabledInk: Color(0xFF7F8F98),
    hairline: Color(0x1FFFFFFF),
    edge: Color(0x2EFFFFFF),
    highlight: Color(0x4DFFFFFF),
    fieldBorder: Color(0xFF3C4C57),
    aquaInk: Color(0xFF5FE6D4),
    azureInk: Color(0xFF8CBEFF),
    violetInk: Color(0xFFBEA8FF),
    amberInk: Color(0xFFFFC772),
    mintInk: Color(0xFF7AE6A9),
    coralInk: Color(0xFFFF97A2),
    glass: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xEB1C2830), Color(0xC7141F26)],
    ),
    acrylic: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xE61C2830), Color(0xD9141F26)],
    ),
    liquid: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xB81C2830), Color(0x99141F26)],
    ),
    rim: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x40FFFFFF), Color(0x14FFFFFF), Color(0x52000000)],
      stops: [0, .45, 1],
    ),
    glint: LinearGradient(
      begin: Alignment(-.57, -1),
      end: Alignment(.57, 1),
      colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
      stops: [0, .3],
    ),
    innerShade: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x00000000), Color(0x33000000)],
    ),
    sombra: Color(0xFF000000),
    veu: Color(0x99000000),
  );
}

/// Obsidian Glass: identidade visual compartilhada pelos fluxos Fluent e
/// Material. No claro, fundo Pearl iluminado e vidro branco fosco; no escuro,
/// fundo Obsidian e vidro grafite. Acentos Aurora vivos onde a cor tem função.
///
/// Os papéis que mudam com a aparência são getters sobre [paleta]; trocar a
/// paleta exige reconstruir a árvore (ver `Aparencia` em `aparencia.dart`).
abstract final class MistakeMapDesign {
  /// Aparência em uso. Só `Aparencia` deve trocar.
  static PaletaMistakeMap paleta = PaletaMistakeMap.claro;

  static bool get escuro => paleta.brightness == Brightness.dark;

  // ─── Paleta base (obrigatória) ────────────────────────────────────────────
  // No claro os tons escuros viram tinta e os claros, superfície; no escuro,
  // o inverso.
  static Color get abyss => paleta.abyss; // títulos e números
  static Color get deep => paleta.deep; // texto forte
  static Color get slate => paleta.slate; // texto corrido
  static Color get steel => paleta.steel; // texto secundário, ícones
  static Color get mist => paleta.mist; // bordas fortes
  static Color get pearl => paleta.pearl; // base do fundo

  // ─── Superfícies derivadas ────────────────────────────────────────────────
  static Color get canvas => paleta.canvas;

  /// Branco puro nas duas aparências: glifo sobre acento ou tinta, brilho.
  /// Para a superfície de um controle ou cartão, use [surface] ou [raised].
  static const white = Color(0xFFFFFFFF);

  /// Tinta escura nas duas aparências, para texto sobre os acentos vivos
  /// (o botão principal em Aqua, por exemplo).
  static const onAccent = Color(0xFF06141B);

  static Color get raised => paleta.raised; // controle em repouso
  static Color get hover => paleta.hover;
  static Color get pressed => paleta.pressed;
  static Color get well => paleta.well; // áreas rebaixadas
  static Color get disabledFill => paleta.disabledFill;
  static Color get disabledInk => paleta.disabledInk;
  static Color get hairline => paleta.hairline; // Deep 8%
  static Color get edge => paleta.edge; // Deep 14%
  static Color get highlight => paleta.highlight; // borda no hover
  static Color get fieldBorder => paleta.fieldBorder;

  // ─── Acentos Aurora: cor só onde tem função ──────────────────────────────
  // Preenchimentos vivos: indicadores, ícones, gráficos e a ação principal.
  static const aqua = Color(0xFF36D6C3); // Início, foco, ação principal
  static const azure = Color(0xFF4C9DFF); // Lista, Cálculo
  static const violet = Color(0xFF9B7BFF); // Mapa e IA, Conceitual
  static const amber = Color(0xFFFFB547); // Caderno, Atenção
  static const mint = Color(0xFF4FD98B);
  static const coral = Color(0xFFFF6F7D);
  static const aurora = LinearGradient(colors: [aqua, azure, violet]);

  // Os mesmos acentos em tinta para texto e ícones (≥ 4,5:1 na superfície):
  // escurecidos no claro, clareados no escuro.
  static Color get aquaInk => paleta.aquaInk;
  static Color get azureInk => paleta.azureInk;
  static Color get violetInk => paleta.violetInk;
  static Color get amberInk => paleta.amberInk;
  static Color get mintInk => paleta.mintInk;
  static Color get coralInk => paleta.coralInk;

  // Estados; sempre acompanhados de rótulo.
  static Color get ok => mintInk;
  static Color get warn => amberInk;
  static Color get bad => coralInk;
  static Color get ai => violetInk;

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
  static Color get navy => abyss; // tinta mais escura e sombras
  static Color get primary => abyss; // títulos e item selecionado
  static Color get content => slate; // texto corrido
  static Color get strong => abyss;
  static Color get background => canvas;
  static Color get surface => raised;
  static Color get border => edge;

  // ─── Cores com alfa que mudam com o tema ─────────────────────────────────
  // No claro dão exatamente os valores fixos antigos (branco ou #11212D com
  // alfa); no escuro, o equivalente sobre o vidro grafite.

  /// Superfície com transparência (vidro fosco): branco no claro.
  static Color pelicula(int alpha) => raised.withAlpha(alpha);

  /// Tom neutro para linhas, trilhos e realces: tinta escura no claro,
  /// branca no escuro.
  static Color tom(int alpha) =>
      (escuro ? white : const Color(0xFF11212D)).withAlpha(alpha);

  /// Reflexo especular do vidro: branco, mais discreto no escuro.
  static Color brilho(int alpha) =>
      white.withAlpha(escuro ? alpha ~/ 3 : alpha);

  /// Sombra projetada; no escuro, mais densa para continuar visível.
  static Color sombra(int alpha) =>
      paleta.sombra.withAlpha(escuro ? (alpha * 2).clamp(0, 255) : alpha);
  static const radius = 16.0;

  // Destaque vivo com texto branco legível em toda a faixa (as tintas do
  // claro, nas duas aparências).
  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF08736A), Color(0xFF1F5FBF), Color(0xFF5532C9)],
  );

  // ─── Aurora Glass: hierarquia Fluent + vidro líquido ─────────────────────
  // L0 Mica: o fundo Aurora fixo. L1 Acrílico: cartões e painéis, quase
  // opacos para o texto. L2 Vidro líquido: só o que flutua (navegação, barras).

  /// Vidro fosco: topo mais opaco, base deixando o fundo aparecer.
  static LinearGradient get glass => paleta.glass;

  /// L1 Acrílico: legível sobre qualquer ponto do fundo.
  static LinearGradient get acrylic => paleta.acrylic;

  /// L2 Vidro líquido: mais transparente, com desfoque e saturação altos.
  static LinearGradient get liquid => paleta.liquid;

  /// Borda especular: a luz pega o topo e a base fica um tom mais escura.
  static LinearGradient get rim => paleta.rim;

  /// Reflexo a 145° (Fluent + Liquid Glass): a luz entra pelo canto superior
  /// esquerdo e some a 30% da superfície.
  static LinearGradient get glint => paleta.glint;

  /// Sombra interna da base: a aresta inferior do vidro escurece um tom.
  static LinearGradient get innerShade => paleta.innerShade;

  /// Véu atrás de diálogos e folhas.
  static Color get veu => paleta.veu;

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
  static List<BoxShadow> get acrylicShadow => [
    BoxShadow(
      color: paleta.sombra.withAlpha(0x38),
      blurRadius: 24,
      spreadRadius: -10,
      offset: Offset(0, 8),
    ),
  ];
  static List<BoxShadow> get liquidShadow => [
    BoxShadow(
      color: paleta.sombra.withAlpha(0x4D),
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
      ? paleta.sombra.withAlpha(escuro ? 0x1F : 0x0F)
      : hover;

  static Color pressedFill(Color rest) => _accented(rest)
      ? Color.lerp(rest, onAccent, .08)!
      : rest.a == 0
      ? paleta.sombra.withAlpha(escuro ? 0x33 : 0x1A)
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
    return contrast(white) >= contrast(onAccent) ? white : onAccent;
  }
}

/// Um acento Aurora com a sua tinta. Serve onde a cor precisa ser constante
/// (enum, valor padrão), mas a tinta muda com o tema claro ou escuro.
enum Acento {
  aqua(MistakeMapDesign.aqua),
  azure(MistakeMapDesign.azure),
  violet(MistakeMapDesign.violet),
  amber(MistakeMapDesign.amber),
  mint(MistakeMapDesign.mint),
  coral(MistakeMapDesign.coral);

  const Acento(this.cor);

  /// Preenchimento vivo (igual nos dois temas).
  final Color cor;

  /// Tinta legível sobre a superfície do tema atual.
  Color get tinta => switch (this) {
    aqua => MistakeMapDesign.aquaInk,
    azure => MistakeMapDesign.azureInk,
    violet => MistakeMapDesign.violetInk,
    amber => MistakeMapDesign.amberInk,
    mint => MistakeMapDesign.mintInk,
    coral => MistakeMapDesign.coralInk,
  };
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
  static TextStyle get tituloPagina => TextStyle(
    fontSize: 24,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: MistakeMapDesign.abyss,
  );
  static TextStyle get tituloSecao => TextStyle(
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: MistakeMapDesign.abyss,
  );
  static TextStyle get tituloComponente => TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: MistakeMapDesign.abyss,
  );
  static TextStyle get corpo => TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 15,
    height: 1.4,
    color: MistakeMapDesign.slate,
  );
  static TextStyle get secundario => TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 13,
    height: 1.35,
    color: MistakeMapDesign.steel,
  );
  static TextStyle get legenda => TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.3,
    color: MistakeMapDesign.steel,
  );

  /// Número de um indicador.
  static TextStyle get numero => TextStyle(
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

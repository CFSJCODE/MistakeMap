import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import 'design_tokens.dart';

/// Camada do Aurora Glass que uma superfície ocupa.
enum GlassTier {
  /// Cartões e painéis de conteúdo (Fluent Acrylic).
  acrylic,

  /// Navegação e controles que flutuam sobre a página (vidro líquido).
  liquid,
}

/// Superfície de vidro compartilhada pelos fluxos Fluent e Material.
///
/// O texto fica sobre um preenchimento quase opaco, então o contraste nunca
/// depende do que está atrás. O desfoque é opcional: listas longas o dispensam,
/// porque o fundo Aurora é fixo e o gradiente já dá o efeito de acrílico.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.tier = GlassTier.acrylic,
    this.radius = MistakeMapDesign.cardRadius,
    this.padding = EdgeInsets.zero,
    this.accent,
    this.blur = false,
    this.shadow = true,
  });

  final Widget child;
  final GlassTier tier;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Acento da seção; tinge o canto superior esquerdo do vidro.
  final Color? accent;
  final bool blur;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    // Alto contraste ligado no aparelho: superfície sólida, sem transparência,
    // tom ou desfoque, e borda visível.
    if (MediaQuery.highContrastOf(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: MistakeMapDesign.white,
          borderRadius: shape,
          border: Border.all(color: MistakeMapDesign.steel),
        ),
        child: Padding(padding: padding, child: child),
      );
    }
    final liquid = tier == GlassTier.liquid;
    final tone = accent;
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        gradient: liquid ? MistakeMapDesign.liquid : MistakeMapDesign.acrylic,
        borderRadius: shape,
      ),
      child: tone == null
          ? Padding(padding: padding, child: child)
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: MistakeMapDesign.tint(tone),
                borderRadius: shape,
              ),
              child: Padding(padding: padding, child: child),
            ),
    );
    if (blur) {
      final sigma = liquid
          ? MistakeMapDesign.liquidBlur
          : MistakeMapDesign.acrylicBlur;
      body = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: body,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: shadow
            ? liquid
                  ? MistakeMapDesign.liquidShadow
                  : MistakeMapDesign.acrylicShadow
            : null,
      ),
      child: CustomPaint(
        foregroundPainter: _RimPainter(radius: radius, liquid: liquid),
        child: ClipRRect(borderRadius: shape, child: body),
      ),
    );
  }
}

/// Borda especular de 1 px; no vidro líquido ganha um reflexo interno no topo.
class _RimPainter extends CustomPainter {
  const _RimPainter({required this.radius, required this.liquid});

  final double radius;
  final bool liquid;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outline = RRect.fromRectAndRadius(
      rect.deflate(.5),
      Radius.circular(radius),
    );
    canvas.drawRRect(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = MistakeMapDesign.rim.createShader(rect),
    );
    if (!liquid) return;
    // A luz refratada desce do topo, como na borda grossa de um vidro.
    canvas.drawRRect(
      outline.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x99FFFFFF), Color(0x00FFFFFF)],
          stops: [0, .35],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) =>
      radius != oldDelegate.radius || liquid != oldDelegate.liquid;
}

/// Destaque em vidro colorido: o gradiente Aurora escurecido, que mantém o
/// texto branco legível, com reflexo no topo e borda clara.
class GlassHero extends StatelessWidget {
  const GlassHero({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: MistakeMapDesign.hero,
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: MistakeMapDesign.violetInk.withValues(alpha: .38),
            blurRadius: 30,
            spreadRadius: -12,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: shape,
        border: Border.all(color: const Color(0x2EFFFFFF)),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          gradient: const RadialGradient(
            center: Alignment(-0.6, -1.2),
            radius: 1.1,
            colors: [Color(0x47FFFFFF), Color(0x00FFFFFF)],
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Bloco de ícone preenchido com o acento da seção e glifo branco.
class GlassIconTile extends StatelessWidget {
  const GlassIconTile({
    super.key,
    required this.icon,
    required this.ink,
    required this.accent,
    this.size = 40,
  });

  final IconData icon;
  final Color ink;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: MistakeMapDesign.iconTile(ink, accent),
      borderRadius: BorderRadius.circular(size * .3),
      border: Border.all(color: const Color(0x40FFFFFF)),
      boxShadow: [
        BoxShadow(
          color: ink.withValues(alpha: .35),
          blurRadius: 14,
          spreadRadius: -6,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Icon(icon, size: size * .5, color: MistakeMapDesign.white),
  );
}

/// Fundo Aurora (L0): canvas Pearl com quatro focos de luz fixos.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, this.child});

  final Widget? child;

  static const _lights = [
    RadialGradient(
      center: Alignment(-1, -1),
      radius: 1.25,
      colors: [Color(0x6B36D6C3), Color(0x0036D6C3)],
    ),
    RadialGradient(
      center: Alignment(1.05, -0.85),
      radius: 1.1,
      colors: [Color(0x5C9B7BFF), Color(0x009B7BFF)],
    ),
    RadialGradient(
      center: Alignment(0.45, 1.15),
      radius: 1.2,
      colors: [Color(0x4D4C9DFF), Color(0x004C9DFF)],
    ),
    RadialGradient(
      center: Alignment(-0.9, 1),
      radius: .75,
      colors: [Color(0x33FFB547), Color(0x00FFB547)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Um gradiente substitui a cor da BoxDecoration: cada luz vai numa camada
    // própria sobre o canvas, sem deixar a janela aparecer.
    Widget layer = child ?? const SizedBox.expand();
    for (final light in _lights.reversed) {
      layer = DecoratedBox(
        decoration: BoxDecoration(gradient: light),
        child: layer,
      );
    }
    return ColoredBox(color: MistakeMapDesign.canvas, child: layer);
  }
}

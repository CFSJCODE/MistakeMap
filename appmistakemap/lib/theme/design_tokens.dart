import 'package:flutter/painting.dart';

/// Identidade da tela Sobre, compartilhada pelos fluxos Fluent e Material.
abstract final class MistakeMapDesign {
  static const navy = Color(0xFF142A4A);
  static const primary = Color(0xFF1E5CA7);
  static const content = Color(0xFF214572);
  static const background = Color(0xFFE8EFF2);
  static const surface = Color(0xFFF7FAFC);
  static const border = Color(0xFFD3DFE9);
  static const radius = 16.0;
  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navy, primary],
  );

  /// Choose ink against the color actually painted during a hover transition.
  /// A direct blue-to-white ink tween loses contrast on the intermediate fill.
  static Color hoverInk(Color fill, Color restingInk, {Color? restingFill}) {
    final painted = Color.alphaBlend(fill, restingFill ?? surface);
    double contrast(Color ink) {
      final a = ink.computeLuminance();
      final b = painted.computeLuminance();
      return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
    }

    if (contrast(restingInk) >= 4.5) return restingInk;
    const white = Color(0xFFFFFFFF);
    const black = Color(0xFF000000);
    if (contrast(white) >= contrast(black)) return white;
    // Darken only as far as necessary before switching to white on dark fills.
    var low = 0.0;
    var high = 1.0;
    for (var step = 0; step < 12; step++) {
      final middle = (low + high) / 2;
      if (contrast(Color.lerp(restingInk, black, middle)!) >= 4.5) {
        high = middle;
      } else {
        low = middle;
      }
    }
    return Color.lerp(restingInk, black, high)!;
  }
}

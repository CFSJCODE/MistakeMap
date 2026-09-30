import 'package:flutter/painting.dart';

/// Aproximações Web RGB inspiradas nos índices de pintura do GTA V.
/// A aparência metálica do jogo depende de iluminação e material.
/// Referência: https://wiki.rage.mp/wiki/Vehicle_Colors
abstract final class Azuis {
  static const midnight = Color(0xFF0A0C17); // Midnight Blue, 141
  static const ultra = Color(0xFF0B9CF1); // Ultra Blue, 70
  static const racing = Color(0xFF2354A1); // Racing Blue, 73
  static const diamond = Color(0xFFD6E7F1); // Diamond Blue, 67

  static const gelo = Color(0xFFF2F8FC);
  static const nevoa = Color(0xFFC6E4F8);
  static const textoSecundario = Color(0xFF456079);
  static const vidro = Color(0xE6F2F8FC);

  static const fundo = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [diamond, gelo, nevoa],
    stops: [0, 0.55, 1],
  );

  // Texto branco continua legível em toda a extensão deste degradê.
  static const destaque = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [midnight, racing],
  );

  static const superficie = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gelo, diamond],
  );

  // Restrito a ornamentos: Ultra não tem contraste para texto branco pequeno.
  static const acento = LinearGradient(colors: [racing, ultra]);
}

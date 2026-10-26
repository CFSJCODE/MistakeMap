import 'package:appmistakemap/main.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppUser reconhece o papel de administrador', () {
    const admin = AppUser(
      id: '1',
      email: 'admin@mistakemap.dev',
      role: 'admin',
    );
    const aluno = AppUser(id: '2', email: 'aluno@mistakemap.dev', role: 'user');

    expect(admin.isAdmin, isTrue);
    expect(aluno.isAdmin, isFalse);
  });

  test('cores de estado são legíveis como texto sobre o branco', () {
    double contraste(m.Color a, m.Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return la > lb ? (la + .05) / (lb + .05) : (lb + .05) / (la + .05);
    }

    // Tons usados como texto em etiquetas, avisos e status (modo claro).
    for (final cor in [
      Cores.vermelho,
      Cores.vermelho400,
      Cores.vermelho600,
      Cores.vermelho700,
      Cores.verde,
      Cores.verde600,
      Cores.laranja,
      Cores.laranja400,
      Cores.laranja700,
      Cores.azul600,
      Cores.cinza,
      Cores.cinza600,
      Cores.cinza700,
      titleBlue,
      contentBlue,
    ]) {
      expect(contraste(cor, Cores.branco), greaterThanOrEqualTo(4.5));
      expect(contraste(cor, kScaffoldBg), greaterThanOrEqualTo(4.5));
    }
  });
}

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

  test('paleta Cores mantém os tons Material usados antes do Fluent UI', () {
    final equivalencias = <m.Color, m.Color>{
      Cores.branco: m.Colors.white,
      Cores.transparente: m.Colors.transparent,
      Cores.vermelho: m.Colors.red,
      Cores.vermelho300: m.Colors.red.shade300,
      Cores.vermelho400: m.Colors.red.shade400,
      Cores.vermelho600: m.Colors.red.shade600,
      Cores.vermelho700: m.Colors.red.shade700,
      Cores.verde: m.Colors.green.shade500,
      Cores.verde600: m.Colors.green.shade600,
      Cores.laranja: m.Colors.orange,
      Cores.laranja400: m.Colors.orange.shade400,
      Cores.laranja700: m.Colors.orange.shade700,
      Cores.ambar: m.Colors.amber,
      Cores.azul600: m.Colors.blue.shade600,
      Cores.cinza: m.Colors.grey.shade500,
      Cores.cinza100: m.Colors.grey.shade100,
      Cores.cinza200: m.Colors.grey.shade200,
      Cores.cinza300: m.Colors.grey.shade300,
      Cores.cinza600: m.Colors.grey.shade600,
      Cores.cinza700: m.Colors.grey.shade700,
    };

    equivalencias.forEach((nova, material) {
      expect(nova.toARGB32(), material.toARGB32());
    });
  });
}

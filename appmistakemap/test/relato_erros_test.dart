import 'package:appmistakemap/team/relato_erros.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assinatura usa o primeiro quadro do app e nunca a mensagem', () {
    final pilha = StackTrace.fromString(
      '#0      List.[] (dart:core-patch/growable_array.dart:264:36)\n'
      '#1      _Grafo.build (package:appmistakemap/ai/force_layout.dart:88:12)\n'
      '#2      main (package:appmistakemap/main.dart:10:3)\n',
    );
    final a = assinaturaDe(RangeError('nota do aluno: segredo'), pilha);
    expect(a.tipo, 'RangeError');
    expect(a.local, 'ai/force_layout.dart:88');
    expect(a.chave, isNot(contains('segredo')));
  });

  test('sem quadro do app, usa o primeiro pacote da pilha', () {
    final pilha = StackTrace.fromString(
      '#0      X.y (package:fluent_ui/src/controls/a.dart:5:1)\n',
    );
    expect(
      assinaturaDe(StateError('x'), pilha).local,
      'package:fluent_ui/src/controls/a.dart',
    );
    expect(assinaturaDe(StateError('x'), null).local, 'desconhecido');
  });

  test('limita repetição por assinatura e por sessão', () async {
    final enviados = <ErroApp>[];
    final r = RelatorErros(
      enviar: (e) async => enviados.add(e),
      porAssinatura: 2,
      porSessao: 3,
    );
    final p1 = StackTrace.fromString('(package:appmistakemap/a.dart:1:1)');
    final p2 = StackTrace.fromString('(package:appmistakemap/b.dart:2:1)');
    final p3 = StackTrace.fromString('(package:appmistakemap/c.dart:3:1)');
    expect(r.registrar(StateError('a'), p1), isTrue);
    expect(r.registrar(StateError('a'), p1), isTrue);
    expect(r.registrar(StateError('a'), p1), isFalse);
    expect(r.registrar(StateError('b'), p2, fatal: true), isTrue);
    expect(r.registrar(StateError('c'), p3), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(enviados, hasLength(3));
    expect(enviados.last.fatal, isTrue);
  });

  test('falha no envio não escapa', () async {
    final r = RelatorErros(enviar: (_) async => throw Exception('rede'));
    expect(r.registrar(StateError('x'), StackTrace.current), isTrue);
    await Future<void>.delayed(Duration.zero);
  });
}

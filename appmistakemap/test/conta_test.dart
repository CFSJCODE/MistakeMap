import 'package:appmistakemap/layout/conta.dart';
import 'package:appmistakemap/school/perfil_modelos.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _render(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    FluentApp(
      home: ScaffoldPage(content: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const estudante = PerfilAtivo('student');
  const professor = PerfilAtivo(
    'teacher',
    escolaId: 'e1',
    escolaNome: 'Colégio Nexo',
  );

  testWidgets('sem conta e sem ações, o botão não aparece', (tester) async {
    await _render(tester, const BotaoConta());
    expect(find.byKey(const Key('botao-conta')), findsNothing);
  });

  testWidgets('um perfil só: menu sem a lista de perfis', (tester) async {
    var sobre = 0;
    await _render(
      tester,
      AcoesConta(
        email: 'aluno@exemplo.dev',
        itens: [
          ItemConta(
            chave: 'sobre',
            icone: WindowsIcons.info,
            rotulo: 'Sobre o MistakeMap',
            onPressed: () => sobre++,
          ),
        ],
        child: ContaAtual(
          perfis: const [estudante],
          ativo: estudante,
          onTrocar: (_) {},
          onSair: () async {},
          child: const BotaoConta(),
        ),
      ),
    );
    await _tocar(tester, find.byKey(const Key('botao-conta')));
    expect(find.text('Sua conta'), findsOneWidget);
    expect(find.text('aluno@exemplo.dev'), findsOneWidget);
    expect(find.text('Perfis desta conta'), findsNothing);
    expect(find.byKey(const Key('conta-aparencia')), findsOneWidget);
    expect(find.byKey(const Key('conta-sair')), findsOneWidget);
    await _tocar(tester, find.byKey(const Key('conta-sobre')));
    expect(sobre, 1);
    expect(find.text('Sua conta'), findsNothing);
  });

  testWidgets('vários perfis: troca na hora, sem login', (tester) async {
    PerfilAtivo? trocado;
    await _render(
      tester,
      ContaAtual(
        perfis: const [estudante, professor],
        ativo: estudante,
        onTrocar: (p) => trocado = p,
        onSair: () async {},
        child: const BotaoConta(),
      ),
    );
    expect(
      find.bySemanticsLabel(RegExp('Perfil atual: Estudante')),
      findsOneWidget,
    );
    await _tocar(tester, find.byKey(const Key('botao-conta')));
    expect(find.text('Perfis desta conta'), findsOneWidget);
    // Papel e escola em linhas separadas: nada corta no celular.
    expect(find.text('Professor'), findsOneWidget);
    expect(find.text('Colégio Nexo'), findsOneWidget);
    // Tocar no perfil atual só fecha.
    await _tocar(tester, find.byKey(const Key('conta-perfil-student')));
    expect(trocado, isNull);
    await _tocar(tester, find.byKey(const Key('botao-conta')));
    await _tocar(tester, find.byKey(const Key('conta-perfil-teacher:e1')));
    expect(trocado?.chave, 'teacher:e1');
  });

  testWidgets('sair pergunta antes e usa o sair da porta', (tester) async {
    var porta = 0;
    var tela = 0;
    await _render(
      tester,
      AcoesConta(
        onSair: () async => tela++,
        child: ContaAtual(
          perfis: const [estudante],
          ativo: estudante,
          onTrocar: (_) {},
          onSair: () async => porta++,
          child: const BotaoConta(),
        ),
      ),
    );
    await _tocar(tester, find.byKey(const Key('botao-conta')));
    await _tocar(tester, find.byKey(const Key('conta-sair')));
    expect(find.text('Deseja sair do MistakeMap neste aparelho?'), findsOne);
    await _tocar(tester, find.text('Cancelar'));
    expect(porta + tela, 0);
    await _tocar(tester, find.byKey(const Key('botao-conta')));
    await _tocar(tester, find.byKey(const Key('conta-sair')));
    await _tocar(tester, find.byKey(const Key('conta-sair-confirmar')));
    expect(porta, 1);
    expect(tela, 0);
  });

  testWidgets('aparência abre a escolha de tema', (tester) async {
    await _render(tester, const AcoesConta(child: BotaoConta()));
    await _tocar(tester, find.byKey(const Key('botao-conta')));
    await _tocar(tester, find.byKey(const Key('conta-aparencia')));
    expect(find.text('Aparência'), findsOneWidget);
    expect(find.byKey(const Key('aparencia-escuro')), findsOneWidget);
  });
}

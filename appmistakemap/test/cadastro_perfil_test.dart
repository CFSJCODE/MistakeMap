import 'package:appmistakemap/main.dart' show temaFluent, temaVidro;
import 'package:appmistakemap/school/escola_repositorio.dart';
import 'package:appmistakemap/school/painel_escola.dart';
import 'package:appmistakemap/school/perfil_modelos.dart';
import 'package:appmistakemap/school/porta_perfil.dart';
import 'package:appmistakemap/school/quem_e_voce.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = '11111111-1111-4111-8111-111111111111';
const _escola = '22222222-2222-4222-8222-222222222222';

class _RepoFalso implements RepositorioEscola {
  _RepoFalso({this.ctx = const ContextoPerfil(), this.falhas = const {}});

  ContextoPerfil ctx;
  final Map<String, String> falhas;
  final chamadas = <(String, DadosEscola)>[];

  @override
  Future<ContextoPerfil> contexto() async => ctx;

  @override
  Future<DadosEscola> executar(
    String acao, [
    DadosEscola dados = const {},
  ]) async {
    chamadas.add((acao, dados));
    final falha = falhas[acao];
    if (falha != null) throw FalhaEscola(falha);
    switch (acao) {
      case 'save_profile':
        return {
          'signup': {
            'persona': dados['persona'],
            'birth_date': dados['birth_date'],
          },
          'roles': [
            if (dados['persona'] == 'coordinator')
              {
                'school_id': _escola,
                'school_name': 'Escola de Robótica',
                'role': 'coordinator',
                'status': 'active',
              },
          ],
        };
      case 'school_overview':
        return {
          'school': {
            'id': _escola,
            'name': 'Escola de Robótica',
            'plan': 'free',
          },
          'members': [
            {'role': 'owner', 'total': 1},
            {'role': 'student', 'total': 12},
          ],
          'invites': [],
          'teams': [],
        };
      case 'create_invite':
        return {'code': 'K7P2M9QRT4WX', 'role': dados['role']};
      case 'request_guardian_consent':
        return {'code': 'ABCDEFGH2345'};
    }
    return {};
  }
}

Future<void> _render(WidgetTester tester, Widget corpo) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1400);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    LiquidGlassWidgets.wrap(
      theme: temaVidro,
      child: FluentApp(theme: temaFluent, home: corpo),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await _settle(tester);
  await tester.tap(alvo);
  await _settle(tester);
}

Future<void> _digitar(WidgetTester tester, String rotulo, String texto) async {
  final campo = find.descendant(
    of: find.widgetWithText(InfoLabel, rotulo),
    matching: find.byType(TextBox),
  );
  await tester.ensureVisible(campo);
  await tester.enterText(campo, texto);
  await _settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('regras do cadastro', () {
    final hoje = DateTime(2026, 11, 11);

    test('data de nascimento DD/MM/AAAA', () {
      expect(
        lerDataNascimento('10/05/2013', hoje: hoje),
        DateTime(2013, 5, 10),
      );
      expect(lerDataNascimento('31/02/2013', hoje: hoje), isNull);
      expect(lerDataNascimento('12/11/2026', hoje: hoje), isNull);
      expect(lerDataNascimento('01/01/1900', hoje: hoje), isNull);
      expect(lerDataNascimento('2013-05-10', hoje: hoje), isNull);
      expect(idadeEm(DateTime(2008, 11, 12), hoje), 17);
      expect(idadeEm(DateTime(2008, 11, 11), hoje), 18);
      expect(dataIso(DateTime(2013, 5, 1)), '2013-05-01');
    });

    test('conta sem perfil e sem papel vê o cadastro; com papel, pula', () {
      expect(const ContextoPerfil().precisaCadastro, isTrue);
      const comConvite = ContextoPerfil(
        papeis: [
          PapelEscola(escolaId: _escola, escolaNome: 'E', papel: 'student'),
        ],
      );
      expect(comConvite.precisaCadastro, isFalse);
      expect(comConvite.perfis.map((p) => p.chave), ['student']);
    });

    test('vários papéis viram perfis do seletor; abre no do cadastro', () {
      const ctx = ContextoPerfil(
        perfil: PerfilCadastro.dono,
        papeis: [
          PapelEscola(
            escolaId: _escola,
            escolaNome: 'Escola A',
            papel: 'owner',
          ),
          PapelEscola(
            escolaId: _escola,
            escolaNome: 'Escola A',
            papel: 'teacher',
          ),
          PapelEscola(
            escolaId: 'x',
            escolaNome: 'B',
            papel: 'it_admin',
            ativo: false,
          ),
        ],
        temFilhos: true,
      );
      expect(ctx.perfis.map((p) => p.chave), [
        'student',
        'owner:$_escola',
        'teacher:$_escola',
        'guardian',
      ]);
      expect(ctx.perfilInicial(null).chave, 'owner:$_escola');
      expect(ctx.perfilInicial('teacher:$_escola').papel, 'teacher');
      expect(ctx.perfilInicial('sumiu').papel, 'owner');
      final volta = ContextoPerfil.deJson(ctx.paraJson());
      expect(volta.perfis.map((p) => p.chave), ctx.perfis.map((p) => p.chave));
      expect(volta.perfil, PerfilCadastro.dono);
    });
  });

  testWidgets('Quem é você? mostra os 7 perfis e marca os só com convite', (
    tester,
  ) async {
    await _render(
      tester,
      TelaQuemEVoce(repositorio: _RepoFalso(), onConcluido: (_) {}),
    );
    expect(find.text('Quem é você?'), findsOneWidget);
    for (final p in PerfilCadastro.values) {
      expect(find.text(p.titulo), findsOneWidget);
    }
    expect(find.text('Só com convite'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'coordenador sem código não avança; com código resgata o convite',
    (tester) async {
      final repo = _RepoFalso();
      ContextoPerfil? concluido;
      await _render(
        tester,
        TelaQuemEVoce(repositorio: repo, onConcluido: (c) => concluido = c),
      );
      await _tocar(tester, find.text('Coordenador'));
      await _tocar(tester, find.text('Continuar'));
      expect(
        find.text('Informe o código do convite enviado pelo dono da escola.'),
        findsOneWidget,
      );
      expect(repo.chamadas, isEmpty);

      await _digitar(tester, 'Código do convite', 'k7p2m9qrt4wx');
      await _tocar(tester, find.text('Continuar'));
      expect(repo.chamadas.map((c) => c.$1), ['redeem_invite', 'save_profile']);
      expect(repo.chamadas.first.$2['persona'], 'coordinator');
      expect(concluido?.perfis.last.papel, 'coordinator');
    },
  );

  testWidgets('convite recusado pelo servidor mostra a mensagem e não grava', (
    tester,
  ) async {
    final repo = _RepoFalso(
      falhas: {'redeem_invite': 'Este convite é para estudante.'},
    );
    await _render(
      tester,
      TelaQuemEVoce(repositorio: repo, onConcluido: (_) {}),
    );
    await _tocar(tester, find.text('TI da escola'));
    await _digitar(tester, 'Código do convite', 'ABCDEFGH2345');
    await _tocar(tester, find.text('Continuar'));
    expect(find.text('Este convite é para estudante.'), findsOneWidget);
    expect(repo.chamadas.map((c) => c.$1), ['redeem_invite']);
  });

  testWidgets('estudante informa o nascimento; sem código estuda sozinho', (
    tester,
  ) async {
    final repo = _RepoFalso();
    await _render(
      tester,
      TelaQuemEVoce(
        repositorio: repo,
        onConcluido: (_) {},
        hoje: DateTime(2026, 11, 11),
      ),
    );
    await _tocar(tester, find.text('Estudante'));
    await _tocar(tester, find.text('Continuar'));
    expect(
      find.text('Informe a data de nascimento (DD/MM/AAAA).'),
      findsOneWidget,
    );
    await _digitar(tester, 'Data de nascimento', '10052013');
    await _tocar(tester, find.text('Continuar'));
    expect(repo.chamadas.single.$1, 'save_profile');
    expect(repo.chamadas.single.$2, {
      'persona': 'student',
      'birth_date': '2013-05-10',
    });
  });

  testWidgets('responsável precisa confirmar o termo antes de enviar', (
    tester,
  ) async {
    final repo = _RepoFalso();
    await _render(
      tester,
      TelaQuemEVoce(repositorio: repo, onConcluido: (_) {}),
    );
    await _tocar(tester, find.text('Pai ou responsável'));
    await _digitar(tester, 'Código', 'ABCDEFGH2345');
    await _tocar(tester, find.text('Continuar'));
    expect(
      find.text('Confirme o termo do responsável para continuar.'),
      findsOneWidget,
    );
    expect(repo.chamadas, isEmpty);
  });

  testWidgets('porta: conta nova vê o cadastro antes do app', (tester) async {
    await _render(
      tester,
      PortaDePerfil(
        usuarioId: _uid,
        repositorio: _RepoFalso(),
        estudante: const Text('APP DO ESTUDANTE'),
      ),
    );
    expect(find.text('Quem é você?'), findsOneWidget);
    expect(find.text('APP DO ESTUDANTE'), findsNothing);
  });

  testWidgets('porta: no app da equipe, conta sem perfil abre direto', (
    tester,
  ) async {
    await _render(
      tester,
      PortaDePerfil(
        usuarioId: _uid,
        repositorio: _RepoFalso(),
        estudante: const Text('APP DO ESTUDANTE'),
        modoEquipe: true,
      ),
    );
    expect(find.text('Quem é você?'), findsNothing);
    expect(find.text('APP DO ESTUDANTE'), findsOneWidget);
  });

  testWidgets('porta: dono abre no painel e troca para estudante no seletor', (
    tester,
  ) async {
    final repo = _RepoFalso(
      ctx: const ContextoPerfil(
        perfil: PerfilCadastro.dono,
        papeis: [
          PapelEscola(
            escolaId: _escola,
            escolaNome: 'Escola de Robótica',
            papel: 'owner',
          ),
        ],
      ),
    );
    await _render(
      tester,
      PortaDePerfil(
        usuarioId: _uid,
        repositorio: repo,
        estudante: const Text('APP DO ESTUDANTE'),
      ),
    );
    expect(find.byType(SeletorPerfil), findsOneWidget);
    expect(find.byType(TelaPainelEscola), findsOneWidget);
    expect(find.text('Painel do dono'), findsOneWidget);
    expect(find.text('Estudante: 12'), findsOneWidget);

    await _tocar(tester, find.byType(ComboBox<String>).first);
    await _tocar(tester, find.text('Estudante').last);
    expect(find.text('APP DO ESTUDANTE'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('perfil_ativo_$_uid'), 'student');
  });

  testWidgets(
    'porta: "Já tenho conta: entrar" guarda o perfil e sai; rodapé no fim',
    (tester) async {
      var saiu = 0;
      await _render(
        tester,
        PortaDePerfil(
          usuarioId: _uid,
          repositorio: _RepoFalso(),
          estudante: const Text('APP DO ESTUDANTE'),
          sair: () async => saiu++,
          rodapeCadastro: const Text('ATUALIZAÇÕES'),
        ),
      );
      expect(find.text('Já tenho conta: entrar'), findsNWidgets(7));
      expect(find.text('ATUALIZAÇÕES'), findsOneWidget);

      await _tocar(tester, find.byKey(const ValueKey('entrar-teacher')));
      expect(saiu, 1);
      expect(
        await const PreferenciasPerfil().perfilPedidoNoLogin(),
        PerfilCadastro.professor,
      );
    },
  );

  testWidgets('porta: no formulário do perfil também dá para entrar', (
    tester,
  ) async {
    var saiu = 0;
    await _render(
      tester,
      PortaDePerfil(
        usuarioId: _uid,
        repositorio: _RepoFalso(),
        estudante: const Text('APP DO ESTUDANTE'),
        sair: () async => saiu++,
      ),
    );
    await _tocar(tester, find.text('Dono da escola'));
    await _tocar(tester, find.text('Já tenho conta de dono da escola: entrar'));
    expect(saiu, 1);
    expect(
      await const PreferenciasPerfil().perfilPedidoNoLogin(),
      PerfilCadastro.dono,
    );
  });

  testWidgets('porta: perfil pedido no login abre direto e é usado uma vez', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'perfil_pedido_login': 'student'});
    final repo = _RepoFalso(
      ctx: const ContextoPerfil(
        perfil: PerfilCadastro.dono,
        papeis: [
          PapelEscola(
            escolaId: _escola,
            escolaNome: 'Escola de Robótica',
            papel: 'owner',
          ),
        ],
      ),
    );
    await _render(
      tester,
      PortaDePerfil(
        usuarioId: _uid,
        repositorio: repo,
        estudante: const Text('APP DO ESTUDANTE'),
      ),
    );
    // Sem o pedido, o dono abriria no painel da escola.
    expect(find.text('APP DO ESTUDANTE'), findsOneWidget);
    expect(find.text('Painel do dono'), findsNothing);
    expect(await const PreferenciasPerfil().perfilPedidoNoLogin(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('perfil_ativo_$_uid'), 'student');
  });

  testWidgets(
    'porta: menor sem consentimento vê o pedido e pode seguir sem IA',
    (tester) async {
      final repo = _RepoFalso(
        ctx: ContextoPerfil(
          perfil: PerfilCadastro.estudante,
          nascimento: DateTime(2013, 5, 10),
          consentimentoPendente: true,
        ),
      );
      await _render(
        tester,
        PortaDePerfil(
          usuarioId: _uid,
          repositorio: repo,
          estudante: const Text('APP DO ESTUDANTE'),
        ),
      );
      expect(
        find.text('Falta o consentimento do seu responsável'),
        findsOneWidget,
      );
      await _tocar(tester, find.text('Gerar código para o responsável'));
      expect(find.text('ABCDEFGH2345'), findsOneWidget);
      await _tocar(tester, find.text('Fechar'));
      await _tocar(tester, find.text('Continuar sem a IA por enquanto'));
      expect(find.text('APP DO ESTUDANTE'), findsOneWidget);
    },
  );

  testWidgets('dono gera convite de coordenação de uso único', (tester) async {
    final repo = _RepoFalso();
    await _render(
      tester,
      TelaPainelEscola(
        perfil: const PerfilAtivo(
          'owner',
          escolaId: _escola,
          escolaNome: 'Escola de Robótica',
        ),
        repositorio: repo,
      ),
    );
    expect(find.text('Convites'), findsOneWidget);
    await _tocar(tester, find.text('Gerar convite'));
    final convite = repo.chamadas.firstWhere((c) => c.$1 == 'create_invite');
    expect(convite.$2['role'], 'coordinator');
    expect(convite.$2['max_uses'], 1);
    expect(find.text('K7P2M9QRT4WX'), findsOneWidget);
  });
}

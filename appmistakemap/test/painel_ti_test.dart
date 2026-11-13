import 'package:appmistakemap/main.dart' show temaFluent, temaVidro;
import 'package:appmistakemap/school/escola_repositorio.dart';
import 'package:appmistakemap/school/painel_escola.dart';
import 'package:appmistakemap/school/painel_ti.dart';
import 'package:appmistakemap/school/perfil_modelos.dart';
import 'package:appmistakemap/school/ti_modelos.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

const _escola = '22222222-2222-4222-8222-222222222222';
const _aluno = '33333333-3333-4333-8333-333333333333';

class _RepoTi implements RepositorioEscola {
  final chamadas = <(String, DadosEscola)>[];

  @override
  Future<ContextoPerfil> contexto() async => const ContextoPerfil();

  @override
  Future<DadosEscola> executar(
    String acao, [
    DadosEscola dados = const {},
  ]) async {
    chamadas.add((acao, dados));
    return switch (acao) {
      'school_overview' => {
        'school': {'id': _escola, 'name': 'Colégio Nexo', 'plan': 'free'},
        'members': [
          {'role': 'it_admin', 'total': 1},
          {'role': 'student', 'total': 3},
        ],
        'invites': [],
        'teams': [],
      },
      'it_licenses' => {
        'plan': 'free',
        'plan_label': 'Grátis',
        'max_users': 5,
        'users_active': 4,
        'users_suspended': 1,
        'by_role': {'student': 3, 'it_admin': 1},
        'max_classes': 1,
        'classes': 1,
        'open_invites': 3,
        'active_students': 2,
        'analyses_pot': 40,
        'analyses_used': 10,
        'extra_analyses': 0,
        'practices_pot': 8,
        'practices_used': 2,
      },
      'it_directory' => {
        'people': [
          {
            'user_id': _aluno,
            'email': 'davi@escola.dev',
            'name': 'Davi Lima',
            'roles': [
              {'role': 'student', 'status': 'active', 'manageable': true},
            ],
            'joined_at': '2026-11-01T10:00:00Z',
            'last_sign_in_at': null,
            'sessions': 2,
            'account_manageable': true,
            'is_me': false,
          },
          {
            'user_id': '44444444-4444-4444-8444-444444444444',
            'email': 'ti@escola.dev',
            'roles': [
              {'role': 'it_admin', 'status': 'active', 'manageable': false},
            ],
            'sessions': 1,
            'account_manageable': false,
            'is_me': true,
          },
        ],
      },
      'it_member_sessions' => {
        'sessions': [
          {
            'created_at': '2026-11-10T10:00:00Z',
            'last_seen_at': '2026-11-12T10:00:00Z',
            'user_agent': 'Mozilla/5.0 (Linux; Android 15) Chrome/140',
            'network': '177.10.x.x',
          },
        ],
      },
      'it_set_status' => {'status': dados['status']},
      'it_import_invites' => {
        'created': 1,
        'rows': [
          {
            'email': 'ana@escola.dev',
            'role': 'student',
            'status': 'created',
            'code': 'ABCDEF123456',
            'expires_at': '2026-12-13T10:00:00Z',
          },
          {'email': 'x', 'role': 'student', 'status': 'invalid_email'},
        ],
      },
      _ => {},
    };
  }
}

Future<void> _render(WidgetTester tester, Widget corpo) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1600);
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

void main() {
  group('planilha de convites', () {
    test('lê ponto e vírgula, vírgula, tabulação, cabeçalho e português', () {
      final linhas = lerPlanilha(
        'E-mail;Papel\n'
        'Ana@Escola.dev;Estudante\n'
        'carlos@escola.dev,Professora\n'
        'mae@escola.dev\tResponsável\n'
        'sem-papel@escola.dev\n'
        '\n'
        'linha ruim\n',
        papelPadrao: 'teacher',
      );
      expect(
        [for (final l in linhas) '${l.email}|${l.papel}'],
        [
          'ana@escola.dev|student',
          'carlos@escola.dev|teacher',
          'mae@escola.dev|guardian',
          'sem-papel@escola.dev|teacher',
          'linha ruim|teacher',
        ],
      );
    });

    test('CSV do lote traz código e motivo em português', () {
      final csv = convitesLoteCsv([
        {
          'email': 'a@b.dev',
          'role': 'student',
          'status': 'created',
          'code': 'ABC123ABC123',
        },
        {'email': 'x', 'role': 'student', 'status': 'invalid_email'},
      ]);
      expect(csv.split('\n').first, 'email;papel;codigo;vence_em;resultado');
      expect(csv, contains('a@b.dev;Estudante;ABC123ABC123;;Convite criado'));
      expect(csv, contains('E-mail inválido'));
    });
  });

  group('modelos', () {
    test('aparelho resumido sem expor o user agent inteiro', () {
      expect(
        resumoAparelho('Mozilla/5.0 (Windows NT 10.0) Chrome/140 Edg/140'),
        'Windows · Edge',
      );
      expect(resumoAparelho('Dart/3.9 (dart:io)'), 'app MistakeMap');
      expect(resumoAparelho(''), 'Aparelho não identificado');
    });

    test('licenças avisam quando convites passam do limite do plano', () {
      final l = LicencasTi.deJson({
        'max_users': 5,
        'users_active': 4,
        'open_invites': 3,
        'analyses_pot': 0,
        'analyses_used': 0,
      });
      expect(l.vagas, 1);
      expect(l.convitesPassamDoLimite, isTrue);
      expect(l.usoAnalises, 0);
    });

    test('auditoria em frases e CSV', () {
      final r = registrosAuditoria({
        'entries': [
          {
            'id': 9,
            'action': 'sessions_revoked',
            'created_at': '2026-11-13T12:00:00Z',
            'actor_email': 'ti@b.dev',
            'target_email': 'al@b.dev',
            'details': {'sessions': 2},
          },
          {
            'id': 8,
            'action': 'invites_imported',
            'details': {'rows': 7, 'created': 6},
          },
        ],
      });
      expect(r.first.descricao, contains('(2)'));
      expect(r.last.descricao, 'Convites em lote: 6 de 7 linhas');
      expect(auditoriaCsv(r), contains('sistema;invites_imported'));
    });

    test('filtro de pessoas por busca, papel e situação', () {
      final p = pessoasDoDiretorio({
        'people': [
          {
            'user_id': 'a',
            'email': 'davi@b.dev',
            'name': 'Davi',
            'roles': [
              {'role': 'student', 'status': 'suspended'},
            ],
          },
        ],
      }).single;
      expect(p.suspensa, isTrue);
      expect(p.combina('dav', 'student', 'suspended'), isTrue);
      expect(p.combina('', 'teacher', 'all'), isFalse);
      expect(p.combina('', null, 'never'), isTrue);
      expect(pessoasCsv([p]), contains('Estudante: suspenso'));
    });
  });

  testWidgets('painel da TI mostra licenças e o aviso de vagas', (
    tester,
  ) async {
    final repo = _RepoTi();
    await _render(
      tester,
      TelaPainelEscola(
        perfil: const PerfilAtivo(
          'it_admin',
          escolaId: _escola,
          escolaNome: 'Colégio Nexo',
        ),
        repositorio: repo,
      ),
    );
    expect(find.text('Licenças e acessos'), findsOneWidget);
    expect(find.text('4 de 5'), findsOneWidget);
    expect(find.textContaining('só 1 vaga'), findsOneWidget);
    expect(find.text('Pessoas e acessos'), findsOneWidget);
    expect(find.text('Convidar em lote'), findsOneWidget);
    expect(find.text('Registro de auditoria'), findsOneWidget);
    expect(repo.chamadas.map((c) => c.$1), contains('it_licenses'));
  });

  testWidgets('professor não vê as ferramentas da TI', (tester) async {
    final repo = _RepoTi();
    await _render(
      tester,
      TelaPainelEscola(
        perfil: const PerfilAtivo('teacher', escolaId: _escola),
        repositorio: repo,
      ),
    );
    expect(find.text('Licenças e acessos'), findsNothing);
    expect(repo.chamadas.map((c) => c.$1), isNot(contains('it_licenses')));
  });

  testWidgets('pessoas: aparelhos, suspensão e cópia da lista', (tester) async {
    final copiado = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiado.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    final repo = _RepoTi();
    await _render(
      tester,
      TelaPessoasTi(
        escolaId: _escola,
        escolaNome: 'Colégio Nexo',
        repositorio: repo,
      ),
    );
    expect(find.text('2 pessoas'), findsOneWidget);
    expect(find.text('ti@escola.dev (você)'), findsOneWidget);

    await _tocar(tester, find.text('Davi Lima'));
    await _tocar(tester, find.text('Ver aparelhos'));
    expect(find.textContaining('Android · Chrome'), findsOneWidget);
    expect(find.textContaining('177.10.x.x'), findsOneWidget);

    await _tocar(tester, find.text('Suspender'));
    await _tocar(tester, find.text('Suspender').last);
    final suspensao = repo.chamadas.lastWhere((c) => c.$1 == 'it_set_status');
    expect(suspensao.$2['status'], 'suspended');
    expect(suspensao.$2['user_id'], _aluno);

    await _tocar(tester, find.byIcon(FluentIcons.copy));
    expect(copiado.single, contains('davi@escola.dev'));
  });

  testWidgets('convites em lote mostram código e motivo por linha', (
    tester,
  ) async {
    final repo = _RepoTi();
    await _render(
      tester,
      TelaConvitesLoteTi(
        escolaId: _escola,
        escolaNome: 'Colégio Nexo',
        repositorio: repo,
      ),
    );
    await tester.enterText(
      find.byType(TextBox).first,
      'ana@escola.dev;estudante\nx;estudante',
    );
    await _settle(tester);
    await _tocar(tester, find.text('Gerar 2 convites'));
    final envio = repo.chamadas.lastWhere((c) => c.$1 == 'it_import_invites');
    expect((envio.$2['rows'] as List).length, 2);
    expect(find.text('ABCDEF123456'), findsOneWidget);
    expect(find.text('E-mail inválido'), findsOneWidget);
  });
}

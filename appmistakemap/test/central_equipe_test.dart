import 'package:appmistakemap/layout/navigation_shell.dart';
import 'package:appmistakemap/team/central_equipe.dart';
import 'package:appmistakemap/team/central_equipe_dados.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _RepoFalso implements RepositorioEquipe {
  int sondas = 0;
  int recomecos = 0;
  bool servidorFalha = false;

  @override
  Future<DadosEquipe> retrato() async => {
    'captured_at': '2026-11-13T02:00:00Z',
    'usage': {
      'profiles': 13,
      'profiles_by_role': {'user': 10, 'admin': 2, 'developer': 1},
      'active_users_7d': 8,
      'attempts_7d': 73,
    },
    'ai': {
      'last_model': 'gemini-2.5-flash',
      'requests_today': {'analysis': 4},
      'models_7d': [
        {'model': 'gemini-2.5-flash', 'analyses': 56},
      ],
      'api_24h': [],
    },
    'pipeline': {'by_status': {}, 'leased_now': 0, 'failures_24h': 0},
    'errors': {
      'total_24h': 2,
      'invalid_ai_output_24h': 1,
      'by_code_24h': [
        {
          'function_name': 'analyze-attempt',
          'code': 'invalid_ai_output',
          'n': 1,
          'last_at': '2026-11-13T01:00:00Z',
        },
      ],
      'recent': [
        {
          'occurred_at': '2026-11-13T01:00:00Z',
          'function_name': 'analyze-attempt',
          'code': 'invalid_ai_output',
          'status': 502,
          'source': 'edge',
        },
      ],
    },
    'cron': [
      {
        'jobname': 'process-batch-every-minute',
        'schedule': '* * * * *',
        'active': true,
        'last_run_at': '2026-11-13T01:59:00Z',
        'last_status': 'succeeded',
        'runs_24h': 1440,
        'failures_24h': 0,
      },
    ],
    'billing': {'invoices': [], 'demo_schools': 2},
    'database': {
      'last_migration': '20261113030000',
      'size_bytes': 81595539,
      'deletion_jobs_pending': 0,
    },
  };

  @override
  Future<List<CheckDiagnostico>> diagnosticosServidor() async {
    if (servidorFalha) throw const FalhaEquipe('sem rede');
    return [
      CheckDiagnostico.doServidor({
        'id': 'rls',
        'title': 'RLS ligada em todas as tabelas',
        'status': 'ok',
        'detail': 'Nenhuma tabela pública sem RLS.',
      }),
      CheckDiagnostico.doServidor({
        'id': 'invalid_ai_output',
        'title': 'Respostas inválidas da IA (24 h)',
        'status': 'warn',
        'detail': '1 ocorrência(s) de invalid_ai_output.',
      }),
    ];
  }

  @override
  Future<DadosEquipe> saudeEdge() async => {
    'database': 'ok',
    'r2': 'ok',
    'http': 200,
  };

  @override
  Future<void> registrarSonda() async => sondas++;

  @override
  Future<DadosEquipe> recomecarDadosDemo() async {
    recomecos++;
    return {'exercises_removed': 3, 'notes_archived': 1, 'examples_created': 6};
  }
}

const _info = InfoBuild(
  versao: '1.0.2',
  build: 3,
  equipe: true,
  release: false,
  plataforma: 'android',
  servidor: 'exemplo.supabase.co',
);

Widget _app(_RepoFalso repo, {String email = 'dev.demo@mistakemap.dev'}) =>
    FluentApp(
      home: ScaffoldPage(
        content: CentralEquipe(
          repositorio: repo,
          info: _info,
          papel: 'developer',
          email: email,
          sessaoValida: () => true,
        ),
      ),
    );

void _telaAlta(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('Saúde mostra uso, IA e rotinas do retrato', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(_RepoFalso()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Semáforo'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('process-batch-every-minute'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('process-batch-every-minute'), findsOneWidget);
  });

  testWidgets('Erros lista invalid_ai_output por função', (tester) async {
    _telaAlta(tester);
    await tester.pumpWidget(_app(_RepoFalso()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('equipe-secao-erros')));
    await tester.pumpAndSettle();
    expect(find.text('invalid_ai_output · analyze-attempt'), findsOneWidget);
    expect(find.text('analyze-attempt → invalid_ai_output'), findsOneWidget);
  });

  testWidgets('Diagnóstico junta checagens do app e do servidor', (
    tester,
  ) async {
    _telaAlta(tester);
    await tester.pumpWidget(_app(_RepoFalso()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('equipe-secao-diagnostico')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rodar diagnósticos'));
    await tester.pumpAndSettle();
    expect(find.text('Resultado: Atenção'), findsOneWidget);
    expect(find.text('Sessão da conta (App)'), findsOneWidget);
    expect(
      find.text('RLS ligada em todas as tabelas (Servidor)'),
      findsOneWidget,
    );
    expect(find.text('Edge Functions (health) (App)'), findsOneWidget);
  });

  testWidgets('Ferramentas: evento de teste e recomeço só em conta de teste', (
    tester,
  ) async {
    _telaAlta(tester);
    final repo = _RepoFalso();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('equipe-secao-ferramentas')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gravar evento de teste'));
    await tester.pumpAndSettle();
    expect(repo.sondas, 1);

    await tester.tap(find.text('Recomeçar meus dados de teste'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recomeçar'));
    await tester.pumpAndSettle();
    expect(repo.recomecos, 1);
    expect(find.textContaining('6 exemplo(s) criado(s)'), findsOneWidget);
  });

  testWidgets('Conta real não pode recomeçar os dados', (tester) async {
    _telaAlta(tester);
    final repo = _RepoFalso();
    await tester.pumpWidget(_app(repo, email: 'alguem@gmail.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('equipe-secao-ferramentas')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recomeçar meus dados de teste'));
    await tester.pumpAndSettle();
    expect(find.text('Recomeçar os dados desta conta?'), findsNothing);
    expect(repo.recomecos, 0);
  });

  test('Relatório de diagnóstico pronto para colar num bug', () async {
    final repo = _RepoFalso()..servidorFalha = true;
    final rodada = await rodarDiagnosticos(
      repo,
      sessaoValida: false,
      agora: () => DateTime.utc(2026, 11, 13),
    );
    expect(rodada.geral, SituacaoCheck.falha);
    final texto = rodada.relatorio(cabecalho: _info.texto());
    expect(texto, contains('Versão: 1.0.2 (build 3)'));
    expect(texto, contains('[Falhou] App: Sessão da conta'));
    expect(texto, contains('[OK] App: Edge Functions (health)'));
  });

  testWidgets('Barra mostra a Central da Equipe no destino da conta', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FluentApp(
        home: AppNavigationShell(
          selectedIndex: 4,
          onSelected: (_) {},
          onAbout: () {},
          hasAdmin: true,
          extraLabel: 'Central da Equipe',
          extraShortLabel: 'Equipe',
          extraIcon: WindowsIcons.developer_tools,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Central da Equipe'), findsOneWidget);
    expect(find.text('Administração'), findsNothing);
  });
}

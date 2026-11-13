import 'package:appmistakemap/main.dart' show temaFluent, temaVidro;
import 'package:appmistakemap/reports/school_reports.dart';
import 'package:appmistakemap/reports/school_reports_page.dart';
import 'package:appmistakemap/school/escola_repositorio.dart';
import 'package:appmistakemap/school/painel_escola.dart';
import 'package:appmistakemap/school/perfil_modelos.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

const _escola = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> _pedagogical({bool mapa = true, bool sample = false}) => {
  'usage': [
    {
      'month': '2026-10-01',
      'active_students': 1910,
      'analyses': 59210,
      'practices': 26740,
      'closed': true,
    },
    {
      'month': '2026-11-01',
      'active_students': 1935,
      'analyses': 23220,
      'practices': 11610,
      'closed': false,
    },
  ],
  'classes': [
    {
      'title': '2º ano A — Robótica móvel',
      'students': 40,
      'active_28d': 30,
      'assignments': 5,
    },
  ],
  'error_students': mapa ? 12 : 3,
  'errors_by_type': mapa
      ? [
          {'error_type': 'calculo', 'errors': 40, 'students': 10},
          {'error_type': 'sinal', 'errors': 12, 'students': 6},
        ]
      : [],
  'concepts': mapa
      ? [
          {
            'concept': 'lei de ohm',
            'errors': 30,
            'students': 9,
            'by_type': {'calculo': 25, 'sinal': 5},
          },
        ]
      : [],
  'sample': sample,
};

Map<String, dynamic> _financial({bool sample = false}) => {
  'cost_by_month': [
    {'month': '2026-10-01', 'active_students': 50, 'total': 600},
    {'month': '2026-11-01', 'active_students': 40, 'total': 480},
  ],
  'invoices_by_month': [
    {'month': '2026-10-01', 'billed': 600, 'paid': 600, 'open': 0},
    {'month': '2026-11-01', 'billed': 480, 'paid': 0, 'open': 480},
  ],
  'by_method': [
    {'method': 'boleto', 'count': 1, 'total': 600},
  ],
  'by_status': [
    {'status': 'paid', 'count': 1, 'total': 600},
    {'status': 'pending', 'count': 1, 'total': 480},
  ],
  'invoices': [
    {
      'reference_month': '2026-11-01',
      'kind': 'checkout',
      'method': 'pix',
      'status': 'pending',
      'total': 480,
      'students': 40,
      'due_date': '2026-11-17',
      'purchase_order': 'PC; 12',
    },
    {
      'reference_month': '2026-10-01',
      'kind': 'monthly',
      'method': 'boleto',
      'status': 'paid',
      'total': 600,
      'students': 50,
      'due_date': '2026-11-10',
      'paid_at': '2026-11-08T12:00:00Z',
      'nfse_number': '123',
    },
  ],
  'sample': sample,
};

Map<String, dynamic> _report({
  bool ped = true,
  bool fin = true,
  bool mapa = true,
  bool demo = false,
}) => {
  'school': {
    'name': 'Escola de Robótica',
    'plan': 'escola',
    'cycle': 'monthly',
    'demo': demo,
  },
  'months': 12,
  'pedagogical': ped ? _pedagogical(mapa: mapa, sample: demo) : null,
  'financial': fin ? _financial(sample: demo) : null,
};

class _FakeReports implements SchoolReportsRepository {
  _FakeReports(this.json);
  Map<String, dynamic> json;
  final calls = <int>[];

  @override
  Future<SchoolReport> load(String schoolId, {int months = 12}) async {
    calls.add(months);
    return SchoolReport.fromJson(json);
  }
}

class _FakeEscola implements RepositorioEscola {
  @override
  Future<ContextoPerfil> contexto() async => const ContextoPerfil();

  @override
  Future<DadosEscola> executar(
    String acao, [
    DadosEscola dados = const {},
  ]) async => {
    'school': {'name': 'Escola de Robótica', 'plan': 'escola'},
    'members': const [],
    'invites': const [],
    'teams': const [],
  };
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

Future<void> _render(WidgetTester tester, Widget body, {double w = 900}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, 1600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    LiquidGlassWidgets.wrap(
      theme: temaVidro,
      child: FluentApp(theme: temaFluent, home: body),
    ),
  );
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await _settle(tester);
  await tester.tap(f);
  await _settle(tester);
}

void main() {
  group('modelos', () {
    final r = SchoolReport.fromJson(_report());

    test('conceitos voltam com siglas e nomes próprios', () {
      expect(conceptTitle('controle pid'), 'Controle PID');
      expect(conceptTitle('dns e dhcp'), 'DNS e DHCP');
      expect(conceptTitle('sub-redes ipv4'), 'Sub-redes IPv4');
      expect(conceptTitle('interrupções (isr)'), 'Interrupções (ISR)');
      expect(
        conceptTitle('conversão binário-decimal'),
        'Conversão binário-decimal',
      );
      expect(conceptTitle('canção'), 'Canção');
      expect(conceptTitle(''), '');
    });

    test('lê as duas seções e os totais', () {
      expect(r.pedagogical!.current!.activeStudents, 1935);
      expect(r.pedagogical!.concepts.single.title, 'Lei de Ohm');
      expect(r.pedagogical!.conceptTypes, ['calculo', 'sinal']);
      expect(r.financial!.paidTotal, 600);
      expect(r.financial!.openTotal, 480);
      // (600 + 480) / (50 + 40)
      expect(r.financial!.costPerActiveStudent, 12);
    });

    test('seção sem permissão fica nula', () {
      final coord = SchoolReport.fromJson(_report(fin: false));
      expect(coord.financial, isNull);
      expect(coord.pedagogical, isNotNull);
    });

    test('CSV das faturas com ponto e vírgula e campo protegido', () {
      final csv = invoicesCsv(r.financial!).split('\n');
      expect(csv.first, startsWith('Mês;Tipo;Alunos;Forma'));
      expect(
        csv[1],
        'nov/26;Contratação;40;Pix;Pendente;480,00;2026-11-17;;"PC; 12";;',
      );
      expect(csv[2], endsWith(';Paga;600,00;2026-11-10;2026-11-08;;;123'));
    });

    test('resumo para compartilhar', () {
      final s = reportSummary(r);
      expect(s, contains('Alunos ativos no mês: 1.935'));
      expect(s, contains('Erro mais comum: Cálculo'));
      expect(s, contains(r'Pago no período: R$ 600,00'));
    });

    test('rótulos de mês e milhar', () {
      expect(monthLabel(DateTime(2026, 7)), 'jul/26');
      expect(formatInt(19156), '19.156');
    });
  });

  testWidgets('dono vê pedagógico e troca para o financeiro', (tester) async {
    final repo = _FakeReports(_report());
    await _render(
      tester,
      SchoolReportsPage(
        schoolId: _escola,
        schoolName: 'Escola de Robótica',
        repository: repo,
      ),
    );
    expect(find.text('Pedagógico'), findsOneWidget);
    expect(find.text('1.935'), findsOneWidget);
    expect(find.text('Mapa de erros da escola'), findsOneWidget);
    expect(find.text('Lei de Ohm'), findsOneWidget);
    expect(find.text('Dados de demonstração'), findsNothing);

    await _tap(tester, find.text('Financeiro'));
    expect(find.text('Forma de pagamento'), findsOneWidget);
    expect(find.textContaining(r'Boleto: R$ 600,00'), findsOneWidget);
    expect(find.text(r'R$ 12,00'), findsOneWidget);
    expect(find.textContaining('NFS-e 123'), findsOneWidget);
  });

  testWidgets('coordenação não vê o financeiro', (tester) async {
    await _render(
      tester,
      SchoolReportsPage(
        schoolId: _escola,
        schoolName: 'Escola de Robótica',
        repository: _FakeReports(_report(fin: false, mapa: false)),
      ),
    );
    expect(find.text('Financeiro'), findsNothing);
    expect(find.textContaining('5 ou mais alunos'), findsWidgets);
    expect(find.textContaining('(hoje: 3)'), findsOneWidget);
  });

  testWidgets('financeiro abre direto nas faturas', (tester) async {
    await _render(
      tester,
      SchoolReportsPage(
        schoolId: _escola,
        schoolName: 'Escola de Robótica',
        repository: _FakeReports(_report(ped: false)),
        initial: ReportSection.pedagogical,
      ),
      w: 390,
    );
    expect(find.text('Pedagógico'), findsNothing);
    expect(find.text('Faturas por mês'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('escola demo mostra o aviso de demonstração', (tester) async {
    await _render(
      tester,
      SchoolReportsPage(
        schoolId: _escola,
        schoolName: 'Colégio Nexo',
        repository: _FakeReports(_report(demo: true)),
      ),
      w: 390,
    );
    expect(find.textContaining('Dados de demonstração'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trocar o período recarrega', (tester) async {
    final repo = _FakeReports(_report());
    await _render(
      tester,
      SchoolReportsPage(
        schoolId: _escola,
        schoolName: 'Escola de Robótica',
        repository: repo,
      ),
    );
    await _tap(tester, find.text('Últimos 12 meses'));
    await _tap(tester, find.text('Últimos 24 meses').last);
    expect(repo.calls, [12, 24]);
  });

  testWidgets('painel: cada papel vê o botão do seu relatório', (tester) async {
    for (final (papel, ped, fin) in [
      ('owner', true, true),
      ('coordinator', true, false),
      ('finance', false, true),
      ('it_admin', false, false),
    ]) {
      await _render(
        tester,
        TelaPainelEscola(
          key: ValueKey(papel),
          perfil: PerfilAtivo(papel, escolaId: _escola),
          repositorio: _FakeEscola(),
          relatorios: _FakeReports(_report()),
        ),
      );
      expect(
        find.text('Relatório pedagógico'),
        ped ? findsOneWidget : findsNothing,
        reason: papel,
      );
      expect(
        find.text('Relatório financeiro'),
        fin ? findsOneWidget : findsNothing,
        reason: papel,
      );
    }
  });

  testWidgets('dono abre o relatório financeiro pelo painel', (tester) async {
    await _render(
      tester,
      TelaPainelEscola(
        perfil: const PerfilAtivo('owner', escolaId: _escola),
        repositorio: _FakeEscola(),
        relatorios: _FakeReports(_report()),
      ),
    );
    await _tap(tester, find.text('Relatório financeiro'));
    expect(find.text('Forma de pagamento'), findsOneWidget);
    expect(find.text('Relatórios'), findsOneWidget);
  });
}

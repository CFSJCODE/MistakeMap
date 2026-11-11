import 'package:appmistakemap/school/school_agreements.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

SchoolAgreementDocument doc(
  String document,
  String title, {
  String version = '1.0',
  DateTime? acceptedAt,
}) => SchoolAgreementDocument(
  document: document,
  version: version,
  title: title,
  body:
      '# $title\n\nVersão $version.\n\n## 1. Papéis\n\nA escola é a **controladora**.\n\n| Suboperador | Local |\n| --- | --- |\n| Supabase | EUA |',
  sha256: '${document.hashCode}'.padLeft(64, '0'),
  effectiveAt: DateTime(2026, 11, 11),
  acceptedAt: acceptedAt,
  signerName: acceptedAt == null ? null : 'Ana Diretora',
  signerRole: acceptedAt == null ? null : 'Diretora',
);

class FakeAgreements implements SchoolAgreementsRepository {
  FakeAgreements(this.documents);
  List<SchoolAgreementDocument> documents;
  final accepted = <(List<String>, String, String)>[];
  SchoolAgreementFailure? acceptFailure;
  List<SchoolAgreementDocument>? afterFailure;

  @override
  Future<List<SchoolAgreementDocument>> status(String schoolId) async =>
      documents;

  @override
  Future<bool> accept(
    String schoolId,
    List<SchoolAgreementDocument> shown, {
    required String signerName,
    required String signerRole,
  }) async {
    if (acceptFailure != null) {
      final failure = acceptFailure!;
      acceptFailure = null;
      if (afterFailure != null) documents = afterFailure!;
      throw failure;
    }
    accepted.add((
      [for (final d in shown) '${d.document}@${d.version}'],
      signerName,
      signerRole,
    ));
    documents = [
      for (final d in documents)
        doc(
          d.document,
          d.title,
          version: d.version,
          acceptedAt: DateTime(2026, 11, 12),
        ),
    ];
    return true;
  }
}

List<SchoolAgreementDocument> pendingDocs() => [
  doc('termos-de-uso', 'Termos de Uso'),
  doc('contrato-saas', 'Contrato SaaS'),
  doc('acordo-tratamento-dados', 'Acordo de Tratamento de Dados'),
];

Future<void> open(
  WidgetTester tester,
  FakeAgreements repo, {
  bool isOwner = true,
  VoidCallback? onAccepted,
}) async {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    FluentApp(
      home: SchoolAgreementsPage(
        schoolId: 'school-a',
        schoolName: 'Escola de Robótica A',
        repository: repo,
        isOwner: isOwner,
        onAccepted: onAccepted,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> checkAll(WidgetTester tester) async {
  for (final finder in find.byType(Checkbox).evaluate().toList()) {
    await tester.tap(find.byWidget(finder.widget));
    await tester.pump();
  }
}

void main() {
  testWidgets('dono vê a escola bloqueada e os 3 documentos pendentes', (
    tester,
  ) async {
    await open(tester, FakeAgreements(pendingDocs()));
    expect(find.text('Uso da escola bloqueado'), findsOneWidget);
    expect(find.textContaining('aceite pendente'), findsNWidgets(3));
    expect(find.byType(Checkbox), findsNWidgets(3));
    expect(
      find.text('Aceitar os 3 documentos e liberar a escola'),
      findsOneWidget,
    );
    // Texto legal renderizado sem os marcadores de Markdown.
    expect(find.text('A escola é a controladora.'), findsWidgets);
    expect(find.text('Supabase · EUA'), findsWidgets);
  });

  testWidgets('aceite exige marcar cada documento e informar nome e cargo', (
    tester,
  ) async {
    final repo = FakeAgreements(pendingDocs());
    var liberou = false;
    await open(tester, repo, onAccepted: () => liberou = true);

    await tester.tap(find.text('Aceitar os 3 documentos e liberar a escola'));
    await tester.pump();
    expect(
      find.text('Marque que leu e aceita cada documento pendente.'),
      findsOneWidget,
    );

    await checkAll(tester);
    await tester.tap(find.text('Aceitar os 3 documentos e liberar a escola'));
    await tester.pump();
    expect(
      find.text(
        'Informe o nome completo e o cargo de quem aceita pela escola.',
      ),
      findsOneWidget,
    );
    expect(repo.accepted, isEmpty);

    final boxes = find.byType(TextBox);
    await tester.enterText(boxes.at(0), '  Ana Diretora ');
    await tester.enterText(boxes.at(1), 'Diretora');
    await tester.tap(find.text('Aceitar os 3 documentos e liberar a escola'));
    await tester.pumpAndSettle();

    expect(repo.accepted, hasLength(1));
    expect(repo.accepted.single.$1, [
      'termos-de-uso@1.0',
      'contrato-saas@1.0',
      'acordo-tratamento-dados@1.0',
    ]);
    expect(repo.accepted.single.$2, 'Ana Diretora');
    expect(liberou, isTrue);
    expect(find.text('Escola liberada'), findsOneWidget);
    expect(find.textContaining('12/11/2026, por Ana Diretora'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('texto atualizado no meio do caminho recarrega a versão nova', (
    tester,
  ) async {
    final repo = FakeAgreements(pendingDocs())
      ..acceptFailure = schoolAgreementFailure('MM409')
      ..afterFailure = [
        doc('termos-de-uso', 'Termos de Uso', version: '1.1'),
        doc(
          'contrato-saas',
          'Contrato SaaS',
          acceptedAt: DateTime(2026, 11, 12),
        ),
        doc(
          'acordo-tratamento-dados',
          'Acordo de Tratamento de Dados',
          acceptedAt: DateTime(2026, 11, 12),
        ),
      ];
    await open(tester, repo);
    await checkAll(tester);
    final boxes = find.byType(TextBox);
    await tester.enterText(boxes.at(0), 'Ana Diretora');
    await tester.enterText(boxes.at(1), 'Diretora');
    await tester.tap(find.text('Aceitar os 3 documentos e liberar a escola'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Os textos foram atualizados'), findsOneWidget);
    expect(find.textContaining('Versão 1.1 · em vigor'), findsOneWidget);
    // A marcação antiga não vale para a versão nova.
    final check = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(check.checked, isFalse);
    expect(find.text('Aceitar e liberar a escola'), findsOneWidget);
  });

  testWidgets('coordenador só consulta: sem caixas nem botão de aceite', (
    tester,
  ) async {
    await open(tester, FakeAgreements(pendingDocs()), isOwner: false);
    expect(
      find.textContaining('quando o dono da escola aceitar'),
      findsOneWidget,
    );
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(TextBox), findsNothing);
  });

  test('códigos do servidor viram frases da tela', () {
    expect(schoolAgreementFailure('MM409').outdated, isTrue);
    expect(
      schoolAgreementFailure('MM403').message,
      'Só o dono da escola pode aceitar o contrato.',
    );
    expect(schoolAgreementFailure(null).message, contains('conexão'));
  });

  test('aceite envia documento, versão e hash do que foi mostrado', () {
    final d = doc('contrato-saas', 'Contrato SaaS');
    expect(d.shown, {
      'document': 'contrato-saas',
      'version': '1.0',
      'sha256': d.sha256,
    });
  });
}

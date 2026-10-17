import 'package:appmistakemap/local/preferencias_caderno.dart';
import 'package:appmistakemap/local/registro_erro.dart';
import 'package:appmistakemap/local/registro_erro_dao.dart';
import 'package:appmistakemap/main.dart';
import 'package:appmistakemap/theme/control_styles.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _user = AppUser(
  id: 'usuario-a',
  email: 'estudante@example.test',
  role: 'user',
);

// DAO em memória: a tela é testada sem abrir o SQLite.
class _DaoFalso extends RegistroErroDao {
  final registros = <RegistroErro>[];
  var _proximoId = 1;

  @override
  Future<int> inserir(RegistroErro registro) async {
    final id = _proximoId++;
    registros.add(registro.copyWith(id: id));
    return id;
  }

  @override
  Future<List<RegistroErro>> listar(
    String usuarioId, {
    bool ocultarRevisados = false,
  }) async => registros
      .where((r) => r.usuarioId == usuarioId)
      .where((r) => !ocultarRevisados || !r.revisado)
      .toList()
      .reversed
      .toList();

  @override
  Future<int> atualizar(RegistroErro registro) async {
    final i = registros.indexWhere((r) => r.id == registro.id);
    registros[i] = registro;
    return 1;
  }

  @override
  Future<int> marcarRevisado(String usuarioId, int id, bool revisado) async {
    final i = registros.indexWhere((r) => r.id == id);
    registros[i] = registros[i].copyWith(revisado: revisado);
    return 1;
  }

  @override
  Future<int> excluir(String usuarioId, int id) async {
    registros.removeWhere((r) => r.id == id);
    return 1;
  }
}

Future<void> _render(WidgetTester tester, Widget page) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    LiquidGlassWidgets.wrap(
      theme: temaVidro,
      child: FluentApp(theme: temaFluent, home: page),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _preencher(WidgetTester tester, String placeholder, String v) =>
    tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextBox && w.placeholder == placeholder,
      ),
      v,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('cria, edita, revisa e exclui um registro', (tester) async {
    final dao = _DaoFalso();
    await _render(tester, TelaCadernoErros(user: _user, dao: dao));
    expect(find.text('Seu caderno ainda está vazio'), findsOneWidget);

    // CREATE
    await tester.tap(find.text('Novo registro').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar registro'));
    await tester.pumpAndSettle();
    expect(find.text('Informe a disciplina'), findsOneWidget);
    expect(dao.registros, isEmpty);

    await _preencher(tester, 'Ex.: Matemática', 'Matemática');
    await _preencher(tester, 'Ex.: Sinal na fórmula de Bhaskara', 'Sinal');
    await _preencher(
      tester,
      'Descreva o erro e como corrigir',
      'Troquei o sinal de b.',
    );
    await tester.tap(find.text('Cálculo'));
    await tester.tap(find.text('Salvar registro'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(dao.registros.single.tipo, TipoErro.calculo);
    expect(find.text('Sinal'), findsOneWidget);
    expect(find.text('Pendente'), findsOneWidget);

    // UPDATE pelo formulário
    await tester.tap(find.text('Sinal'));
    await tester.pumpAndSettle();
    expect(find.text('Editar registro'), findsOneWidget);
    await _preencher(tester, 'Ex.: Sinal na fórmula de Bhaskara', 'Sinal de b');
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text('Sinal de b'), findsOneWidget);

    // UPDATE pelo menu
    await tester.tap(find.byTooltip('Opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcar como revisado'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(dao.registros.single.revisado, isTrue);
    expect(find.text('Revisado'), findsOneWidget);

    // DELETE
    await tester.tap(find.byTooltip('Opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MistakeMapFilledButton, 'Excluir'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(dao.registros, isEmpty);
    expect(find.text('Seu caderno ainda está vazio'), findsOneWidget);
  });

  testWidgets('o filtro "Ocultar revisados" fica salvo', (tester) async {
    final dao = _DaoFalso();
    final agora = DateTime(2026, 10, 17);
    await dao.inserir(
      RegistroErro(
        usuarioId: _user.id,
        disciplina: 'Química',
        titulo: 'Já revisado',
        descricao: 'Balanceamento.',
        tipo: TipoErro.conceitual,
        revisado: true,
        criadoEm: agora,
        atualizadoEm: agora,
      ),
    );
    await _render(tester, TelaCadernoErros(user: _user, dao: dao));
    expect(find.text('Já revisado'), findsOneWidget);

    await tester.tap(find.byTooltip('Ocultar revisados'));
    await tester.pumpAndSettle();
    expect(find.text('Já revisado'), findsNothing);
    expect(await const PreferenciasCaderno().ocultarRevisados(), isTrue);

    // Reabrir a tela lê a preferência salva.
    await _render(tester, const SizedBox());
    await _render(tester, TelaCadernoErros(user: _user, dao: dao));
    expect(find.text('Já revisado'), findsNothing);
    expect(find.byTooltip('Mostrar revisados'), findsOneWidget);
  });
}

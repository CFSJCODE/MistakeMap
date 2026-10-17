import 'package:appmistakemap/local/banco_local.dart';
import 'package:appmistakemap/local/preferencias_caderno.dart';
import 'package:appmistakemap/local/registro_erro.dart';
import 'package:appmistakemap/local/registro_erro_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _usuario = 'usuario-a';
const _outro = 'usuario-b';

RegistroErro _registro({
  String usuario = _usuario,
  String disciplina = 'Matemática',
  String titulo = 'Sinal na Bhaskara',
  TipoErro tipo = TipoErro.calculo,
  DateTime? quando,
}) {
  final data = quando ?? DateTime(2026, 10, 17, 10);
  return RegistroErro(
    usuarioId: usuario,
    disciplina: disciplina,
    titulo: titulo,
    descricao: 'Esqueci de trocar o sinal de b.',
    tipo: tipo,
    criadoEm: data,
    atualizadoEm: data,
  );
}

void main() {
  late BancoLocal banco;
  late RegistroErroDao dao;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    // Banco novo em memória a cada teste, sem tocar no disco.
    banco = BancoLocal(
      fabrica: databaseFactoryFfiNoIsolate,
      caminho: inMemoryDatabasePath,
    );
    dao = RegistroErroDao(banco);
  });

  tearDown(() => banco.fechar());

  test('cria as tabelas da versão 1 com a chave estrangeira ligada', () async {
    final db = await banco.banco;
    final tabelas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    expect(tabelas.map((t) => t['name']), ['disciplinas', 'registros_erro']);
    expect(await db.getVersion(), BancoLocal.versao);
    final fk = await db.rawQuery('PRAGMA foreign_keys');
    expect(fk.first.values.first, 1);
  });

  test('CRUD completo de um registro', () async {
    // CREATE
    final id = await dao.inserir(_registro());
    expect(id, greaterThan(0));

    // READ
    final lido = await dao.buscarPorId(_usuario, id);
    expect(lido, isNotNull);
    expect(lido!.titulo, 'Sinal na Bhaskara');
    expect(lido.disciplina, 'Matemática');
    expect(lido.tipo, TipoErro.calculo);
    expect(lido.revisado, isFalse);

    // UPDATE
    final alteradas = await dao.atualizar(
      lido.copyWith(
        titulo: 'Sinal de b',
        disciplina: 'Física',
        tipo: TipoErro.atencao,
        revisado: true,
      ),
    );
    expect(alteradas, 1);
    final editado = await dao.buscarPorId(_usuario, id);
    expect(editado!.titulo, 'Sinal de b');
    expect(editado.disciplina, 'Física');
    expect(editado.tipo, TipoErro.atencao);
    expect(editado.revisado, isTrue);
    // A disciplina antiga ficou sem registros e foi removida.
    expect((await dao.listarDisciplinas(_usuario)).map((d) => d.nome), [
      'Física',
    ]);

    // DELETE
    expect(await dao.excluir(_usuario, id), 1);
    expect(await dao.buscarPorId(_usuario, id), isNull);
    expect(await dao.listarDisciplinas(_usuario), isEmpty);
  });

  test('reaproveita a disciplina de mesmo nome', () async {
    await dao.inserir(_registro(titulo: 'A'));
    await dao.inserir(_registro(titulo: 'B', disciplina: ' Matemática '));
    expect(await dao.listarDisciplinas(_usuario), hasLength(1));
  });

  test('lista do mais recente ao mais antigo e filtra revisados', () async {
    final antigo = await dao.inserir(
      _registro(titulo: 'Antigo', quando: DateTime(2026, 10, 1)),
    );
    await dao.inserir(
      _registro(titulo: 'Novo', quando: DateTime(2026, 10, 15)),
    );
    expect((await dao.listar(_usuario)).map((r) => r.titulo), [
      'Novo',
      'Antigo',
    ]);

    await dao.marcarRevisado(_usuario, antigo, true);
    final pendentes = await dao.listar(_usuario, ocultarRevisados: true);
    expect(pendentes.map((r) => r.titulo), ['Novo']);
    expect(await dao.listar(_usuario), hasLength(2));
  });

  test('um usuário não lê nem apaga registros de outro', () async {
    final id = await dao.inserir(_registro());
    await dao.inserir(_registro(usuario: _outro, titulo: 'Do outro'));

    expect((await dao.listar(_usuario)).map((r) => r.titulo), [
      'Sinal na Bhaskara',
    ]);
    expect(await dao.buscarPorId(_outro, id), isNull);
    expect(await dao.excluir(_outro, id), 0);
    expect(await dao.buscarPorId(_usuario, id), isNotNull);
  });

  test('o banco recusa tipo de erro fora da lista (CHECK)', () async {
    await dao.inserir(_registro());
    final db = await banco.banco;
    expect(
      () => db.rawUpdate("UPDATE registros_erro SET tipo_erro = 'outro'"),
      throwsA(isA<DatabaseException>()),
    );
  });

  group('PreferenciasCaderno (shared_preferences)', () {
    test('lembra o filtro "Ocultar revisados"', () async {
      SharedPreferences.setMockInitialValues({});
      const prefs = PreferenciasCaderno();
      expect(await prefs.ocultarRevisados(), isFalse);

      await prefs.salvarOcultarRevisados(true);
      expect(await prefs.ocultarRevisados(), isTrue);

      await prefs.limpar();
      expect(await prefs.ocultarRevisados(), isFalse);
    });
  });
}

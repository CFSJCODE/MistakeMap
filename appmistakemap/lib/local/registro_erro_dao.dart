import 'package:sqflite/sqflite.dart';

import 'banco_local.dart';
import 'registro_erro.dart';

/// DAO do caderno de erros: as operações CRUD sobre o SQLite local.
///
/// Toda consulta filtra por usuario_id, então duas contas no mesmo aparelho
/// não veem os registros uma da outra.
class RegistroErroDao {
  RegistroErroDao([BancoLocal? banco]) : _banco = banco ?? BancoLocal.instancia;

  final BancoLocal _banco;

  static const String _tabela = 'registros_erro';

  /// CREATE: grava o registro e devolve o id gerado pelo AUTOINCREMENT.
  Future<int> inserir(RegistroErro registro) async {
    final db = await _banco.banco;
    return db.transaction((txn) async {
      final disciplinaId = await _idDaDisciplina(
        txn,
        registro.usuarioId,
        registro.disciplina,
      );
      final mapa = registro.toMap(disciplinaId: disciplinaId)..remove('id');
      return txn.insert(_tabela, mapa);
    });
  }

  /// READ (todos): JOIN com disciplinas, do mais recente ao mais antigo.
  Future<List<RegistroErro>> listar(
    String usuarioId, {
    bool ocultarRevisados = false,
  }) async {
    final db = await _banco.banco;
    final linhas = await db.rawQuery(
      'SELECT r.*, d.nome AS disciplina '
      'FROM registros_erro r '
      'JOIN disciplinas d ON d.id = r.disciplina_id '
      'WHERE r.usuario_id = ? ${ocultarRevisados ? 'AND r.revisado = 0 ' : ''}'
      'ORDER BY r.atualizado_em DESC, r.id DESC',
      [usuarioId],
    );
    return linhas.map(RegistroErro.fromMap).toList();
  }

  /// READ (um): busca pelo id com o curinga ? em where/whereArgs.
  Future<RegistroErro?> buscarPorId(String usuarioId, int id) async {
    final db = await _banco.banco;
    final linhas = await db.rawQuery(
      'SELECT r.*, d.nome AS disciplina '
      'FROM registros_erro r '
      'JOIN disciplinas d ON d.id = r.disciplina_id '
      'WHERE r.usuario_id = ? AND r.id = ?',
      [usuarioId, id],
    );
    return linhas.isEmpty ? null : RegistroErro.fromMap(linhas.first);
  }

  /// UPDATE: regrava os campos e devolve quantas linhas mudaram (0 ou 1).
  Future<int> atualizar(RegistroErro registro) async {
    final id = registro.id;
    if (id == null) throw ArgumentError('Registro sem id não pode ser editado');
    final db = await _banco.banco;
    return db.transaction((txn) async {
      final disciplinaId = await _idDaDisciplina(
        txn,
        registro.usuarioId,
        registro.disciplina,
      );
      final alteradas = await txn.update(
        _tabela,
        registro.toMap(disciplinaId: disciplinaId)..remove('id'),
        where: 'id = ? AND usuario_id = ?',
        whereArgs: [id, registro.usuarioId],
      );
      await _removerDisciplinasVazias(txn, registro.usuarioId);
      return alteradas;
    });
  }

  /// UPDATE parcial usado pelo menu "Marcar como revisado/pendente".
  Future<int> marcarRevisado(String usuarioId, int id, bool revisado) async {
    final db = await _banco.banco;
    return db.update(
      _tabela,
      {
        'revisado': revisado ? 1 : 0,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND usuario_id = ?',
      whereArgs: [id, usuarioId],
    );
  }

  /// DELETE: apaga o registro e a disciplina que ficou sem registros.
  Future<int> excluir(String usuarioId, int id) async {
    final db = await _banco.banco;
    return db.transaction((txn) async {
      final apagadas = await txn.delete(
        _tabela,
        where: 'id = ? AND usuario_id = ?',
        whereArgs: [id, usuarioId],
      );
      await _removerDisciplinasVazias(txn, usuarioId);
      return apagadas;
    });
  }

  /// Disciplinas do usuário em ordem alfabética (sugestões do formulário).
  Future<List<Disciplina>> listarDisciplinas(String usuarioId) async {
    final db = await _banco.banco;
    final linhas = await db.query(
      'disciplinas',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'nome COLLATE NOCASE',
    );
    return linhas.map(Disciplina.fromMap).toList();
  }

  // Reaproveita a disciplina de mesmo nome ou cria uma nova.
  Future<int> _idDaDisciplina(
    DatabaseExecutor db,
    String usuarioId,
    String nome,
  ) async {
    final limpo = nome.trim();
    final existente = await db.query(
      'disciplinas',
      columns: ['id'],
      where: 'usuario_id = ? AND nome = ?',
      whereArgs: [usuarioId, limpo],
      limit: 1,
    );
    if (existente.isNotEmpty) return existente.first['id'] as int;
    return db.insert(
      'disciplinas',
      Disciplina(usuarioId: usuarioId, nome: limpo).toMap(),
    );
  }

  Future<void> _removerDisciplinasVazias(
    DatabaseExecutor db,
    String usuarioId,
  ) => db.delete(
    'disciplinas',
    where:
        'usuario_id = ? AND id NOT IN '
        '(SELECT disciplina_id FROM registros_erro)',
    whereArgs: [usuarioId],
  );
}

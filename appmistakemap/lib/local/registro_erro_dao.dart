import 'package:sqflite/sqflite.dart';

import '../sync/conexao.dart' show novoUuid;
import 'banco_local.dart';
import 'registro_erro.dart';

/// DAO do caderno de erros: as operações CRUD sobre o SQLite local.
///
/// Toda consulta filtra por usuario_id, então duas contas no mesmo aparelho
/// não veem os registros uma da outra. Toda escrita marca o registro como
/// `pendente`, e a sincronização (lib/sync/caderno_sync.dart) leva a mudança
/// para o Supabase. Registros já enviados não são apagados na hora: viram
/// tombstone (`excluido_em`) até a exclusão chegar ao servidor.
class RegistroErroDao {
  RegistroErroDao([BancoLocal? banco]) : _banco = banco ?? BancoLocal.instancia;

  final BancoLocal _banco;

  static const String _tabela = 'registros_erro';

  /// Registros visíveis: sem tombstone.
  static const String _vivo = 'r.excluido_em IS NULL';

  /// CREATE: grava o registro e devolve o id gerado pelo AUTOINCREMENT.
  Future<int> inserir(RegistroErro registro) async {
    final db = await _banco.banco;
    return db.transaction((txn) async {
      final disciplinaId = await idDaDisciplina(
        txn,
        registro.usuarioId,
        registro.disciplina,
      );
      final mapa = registro.toMap(disciplinaId: disciplinaId)
        ..remove('id')
        ..['uid'] = registro.uid ?? novoUuid()
        ..['pendente'] = 1;
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
      'WHERE r.usuario_id = ? AND $_vivo '
      '${ocultarRevisados ? 'AND r.revisado = 0 ' : ''}'
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
      'WHERE r.usuario_id = ? AND r.id = ? AND $_vivo',
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
      final disciplinaId = await idDaDisciplina(
        txn,
        registro.usuarioId,
        registro.disciplina,
      );
      // O uid nunca muda: é ele que liga o registro ao servidor.
      final mapa = registro.toMap(disciplinaId: disciplinaId)
        ..remove('id')
        ..remove('uid')
        ..['pendente'] = 1;
      final alteradas = await txn.update(
        _tabela,
        mapa,
        where: 'id = ? AND usuario_id = ? AND excluido_em IS NULL',
        whereArgs: [id, registro.usuarioId],
      );
      await removerDisciplinasVazias(txn, registro.usuarioId);
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
        'pendente': 1,
      },
      where: 'id = ? AND usuario_id = ? AND excluido_em IS NULL',
      whereArgs: [id, usuarioId],
    );
  }

  /// DELETE: some da lista na hora. Um registro que nunca chegou ao servidor
  /// sai do banco; um já enviado vira tombstone até a exclusão subir, para os
  /// outros aparelhos também apagarem.
  Future<int> excluir(String usuarioId, int id) async {
    final db = await _banco.banco;
    return db.transaction((txn) async {
      final agora = DateTime.now().toIso8601String();
      final marcadas = await txn.update(
        _tabela,
        {'excluido_em': agora, 'atualizado_em': agora, 'pendente': 1},
        where:
            'id = ? AND usuario_id = ? AND no_servidor = 1 '
            'AND excluido_em IS NULL',
        whereArgs: [id, usuarioId],
      );
      final apagadas = await txn.delete(
        _tabela,
        where:
            'id = ? AND usuario_id = ? AND no_servidor = 0 '
            'AND excluido_em IS NULL',
        whereArgs: [id, usuarioId],
      );
      await removerDisciplinasVazias(txn, usuarioId);
      return marcadas + apagadas;
    });
  }

  /// Disciplinas do usuário em ordem alfabética (sugestões do formulário).
  /// Só as que têm algum registro visível.
  Future<List<Disciplina>> listarDisciplinas(String usuarioId) async {
    final db = await _banco.banco;
    final linhas = await db.rawQuery(
      'SELECT d.* FROM disciplinas d WHERE d.usuario_id = ? AND EXISTS '
      '(SELECT 1 FROM registros_erro r '
      'WHERE r.disciplina_id = d.id AND $_vivo) '
      'ORDER BY d.nome COLLATE NOCASE',
      [usuarioId],
    );
    return linhas.map(Disciplina.fromMap).toList();
  }

  /// Reaproveita a disciplina de mesmo nome ou cria uma nova.
  static Future<int> idDaDisciplina(
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

  /// Tombstones ainda seguram a disciplina (ON DELETE CASCADE apagaria a
  /// exclusão antes de ela subir); ela sai quando o último registro sai.
  static Future<void> removerDisciplinasVazias(
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

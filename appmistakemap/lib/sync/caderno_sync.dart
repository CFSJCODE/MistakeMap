import 'package:sqflite/sqflite.dart';

import '../local/banco_local.dart';
import '../local/registro_erro_dao.dart';
import 'armazem_sync.dart';
import 'remoto_sync.dart';

/// Resultado de uma rodada de sincronização do caderno.
class ResultadoCaderno {
  const ResultadoCaderno({this.alterados = 0, this.excluidosRemotamente = 0});

  /// Registros do aparelho que mudaram por causa do servidor.
  final int alterados;

  /// Registros que estavam visíveis aqui e foram excluídos em outro aparelho.
  final int excluidosRemotamente;

  bool get mudou => alterados > 0 || excluidosRemotamente > 0;
}

/// Sincroniza o Caderno de erros (SQLite `registros_erro`) com a tabela
/// `error_notes` do Supabase.
///
/// 1. **Envio**: os registros `pendente = 1` (inclusive tombstones) sobem
///    com upsert. Em seguida o aparelho relê do servidor esses mesmos ids e
///    aplica a versão de lá, porque o servidor pode ter ignorado a escrita
///    (exclusão definitiva ou edição mais velha que a gravada).
/// 2. **Recebimento**: lê o que mudou no servidor desde o último cursor
///    (`synced_at`, relógio do servidor) e mescla registro a registro.
///
/// Regras da mesclagem, as mesmas do servidor (guard_error_note):
/// * exclusão vence sempre, dos dois lados, e não tem volta;
/// * entre duas edições vence a de `updated_at` mais recente (LWW);
/// * alteração local ainda não enviada só é mantida se for mais nova.
class SincronizacaoCaderno {
  SincronizacaoCaderno(this._banco) : _estado = ArmazemSync(_banco);

  final BancoLocal _banco;
  final ArmazemSync _estado;

  static const chaveCursor = 'caderno_cursor';

  /// Folga na releitura: escritas concorrentes podem confirmar fora de ordem.
  static const margem = Duration(seconds: 5);
  static const lote = 200;

  Future<ResultadoCaderno> sincronizar(
    String usuarioId,
    RemotoSync remoto,
  ) async {
    final contagem = _Contagem();
    await _enviar(usuarioId, remoto, contagem);
    await _receber(usuarioId, remoto, contagem);
    return ResultadoCaderno(
      alterados: contagem.alterados,
      excluidosRemotamente: contagem.excluidos,
    );
  }

  // ─── Envio ────────────────────────────────────────────────────────────────

  Future<void> _enviar(
    String usuarioId,
    RemotoSync remoto,
    _Contagem contagem,
  ) async {
    final db = await _banco.banco;
    var ultimoId = 0;
    while (true) {
      final linhas = await db.rawQuery(
        'SELECT r.*, d.nome AS disciplina FROM registros_erro r '
        'JOIN disciplinas d ON d.id = r.disciplina_id '
        'WHERE r.usuario_id = ? AND r.pendente = 1 AND r.id > ? '
        'ORDER BY r.id LIMIT $lote',
        [usuarioId, ultimoId],
      );
      if (linhas.isEmpty) return;
      final primeiroId = linhas.first['id'] as int;
      ultimoId = linhas.last['id'] as int;
      // A partir daqui o registro pode existir no servidor mesmo que a
      // resposta se perca: excluir passa a deixar tombstone, senão a próxima
      // leitura traria a cópia do servidor de volta.
      await db.rawUpdate(
        'UPDATE registros_erro SET no_servidor = 1 '
        'WHERE usuario_id = ? AND pendente = 1 AND id BETWEEN ? AND ?',
        [usuarioId, primeiroId, ultimoId],
      );
      await remoto.enviarNotas([
        for (final l in linhas) paraServidor(l, usuarioId),
      ]);
      final enviados = {for (final l in linhas) l['uid'] as String: l};
      final confirmadas = await remoto.buscarNotas(
        usuarioId,
        ids: enviados.keys.toList(),
        limite: enviados.length,
      );
      final reenviar = <Map<String, Object?>>[];
      await db.transaction((txn) async {
        for (final remota in confirmadas) {
          final uid = remota['id'] as String;
          final sumiu = await _aplicar(
            txn,
            usuarioId,
            remota,
            contagem,
            enviado: enviados[uid],
          );
          // Apagado aqui enquanto subia: a exclusão vai atrás.
          if (sumiu) reenviar.add(_tombstone(remota));
        }
        await RegistroErroDao.removerDisciplinasVazias(txn, usuarioId);
      });
      if (reenviar.isNotEmpty) await remoto.enviarNotas(reenviar);
      if (linhas.length < lote) return;
    }
  }

  /// Linha do SQLite no formato de `error_notes`. Datas locais viram UTC.
  static Map<String, Object?> paraServidor(
    Map<String, Object?> l,
    String usuarioId,
  ) {
    final excluido = l['excluido_em'] as String?;
    return {
      'id': l['uid'],
      'user_id': usuarioId,
      'subject': l['disciplina'],
      'title': l['titulo'],
      'description': l['descricao'],
      'error_type': l['tipo_erro'],
      'reviewed': l['revisado'] == 1,
      'created_at': _utc(l['criado_em'] as String),
      'updated_at': _utc(l['atualizado_em'] as String),
      'deleted_at': excluido == null ? null : _utc(excluido),
    };
  }

  static Map<String, Object?> _tombstone(Map<String, dynamic> remota) {
    final agora = DateTime.now().toUtc().toIso8601String();
    return {...remota, 'updated_at': agora, 'deleted_at': agora}
      ..remove('synced_at');
  }

  // ─── Recebimento ──────────────────────────────────────────────────────────

  Future<void> _receber(
    String usuarioId,
    RemotoSync remoto,
    _Contagem contagem,
  ) async {
    final salvo = await _estado.lerEstado(usuarioId, chaveCursor);
    var desde = salvo == null ? null : DateTime.parse(salvo).subtract(margem);
    DateTime? maior = salvo == null ? null : DateTime.parse(salvo);
    final db = await _banco.banco;
    while (true) {
      final pagina = await remoto.buscarNotas(
        usuarioId,
        desde: desde,
        limite: lote,
      );
      if (pagina.isEmpty) break;
      await db.transaction((txn) async {
        for (final remota in pagina) {
          await _aplicar(txn, usuarioId, remota, contagem);
        }
        await RegistroErroDao.removerDisciplinasVazias(txn, usuarioId);
      });
      final ultimo = DateTime.parse(pagina.last['synced_at'] as String);
      if (maior == null || ultimo.isAfter(maior)) maior = ultimo;
      if (pagina.length < lote || !ultimo.isAfter(desde ?? DateTime(0))) {
        break;
      }
      desde = ultimo;
    }
    if (maior != null) {
      await _estado.gravarEstado(
        usuarioId,
        chaveCursor,
        maior.toUtc().toIso8601String(),
      );
    }
  }

  // ─── Mesclagem ────────────────────────────────────────────────────────────

  /// Aplica a versão do servidor a um registro. Com [enviado], é a resposta
  /// ao envio dessa linha. Devolve true quando o registro foi apagado aqui
  /// durante o envio e o servidor ainda o tem vivo.
  Future<bool> _aplicar(
    DatabaseExecutor txn,
    String usuarioId,
    Map<String, dynamic> remota,
    _Contagem contagem, {
    Map<String, Object?>? enviado,
  }) async {
    final uid = remota['id'] as String;
    final linhas = await txn.query(
      'registros_erro',
      where: 'uid = ? AND usuario_id = ?',
      whereArgs: [uid, usuarioId],
    );
    final local = linhas.firstOrNull;

    // Exclusão é definitiva: some daqui também, mesmo com edição pendente.
    if (remota['deleted_at'] != null) {
      if (local == null) return false;
      if (local['excluido_em'] == null) contagem.excluidos++;
      await txn.delete(
        'registros_erro',
        where: 'id = ?',
        whereArgs: [local['id']],
      );
      return false;
    }

    if (local == null) {
      if (enviado != null) return true;
      await txn.insert('registros_erro', {
        'usuario_id': usuarioId,
        ...await _campos(txn, usuarioId, remota),
        'uid': uid,
        'criado_em': _local(remota['created_at'] as String),
        'pendente': 0,
        'no_servidor': 1,
      });
      contagem.alterados++;
      return false;
    }

    // Exclusão local ainda não enviada vence a versão viva do servidor.
    if (local['excluido_em'] != null) {
      await _marcarNoServidor(txn, local['id'] as int);
      return false;
    }

    final semMudancaDesdeEnvio =
        enviado != null &&
        local['atualizado_em'] == enviado['atualizado_em'] &&
        local['excluido_em'] == enviado['excluido_em'];
    final localMaisNovo =
        local['pendente'] == 1 &&
        DateTime.parse(local['atualizado_em'] as String)
            .toUtc()
            .isAfter(DateTime.parse(remota['updated_at'] as String));
    if (!semMudancaDesdeEnvio && localMaisNovo) {
      await _marcarNoServidor(txn, local['id'] as int);
      return false;
    }

    final campos = await _campos(txn, usuarioId, remota);
    final mudou = campos.entries.any((c) => local[c.key] != c.value);
    await txn.update(
      'registros_erro',
      {...campos, 'pendente': 0, 'no_servidor': 1},
      where: 'id = ?',
      whereArgs: [local['id']],
    );
    if (mudou) contagem.alterados++;
    return false;
  }

  Future<Map<String, Object?>> _campos(
    DatabaseExecutor txn,
    String usuarioId,
    Map<String, dynamic> remota,
  ) async => {
    'disciplina_id': await RegistroErroDao.idDaDisciplina(
      txn,
      usuarioId,
      remota['subject'] as String,
    ),
    'titulo': remota['title'],
    'descricao': remota['description'],
    'tipo_erro': remota['error_type'],
    'revisado': remota['reviewed'] == true ? 1 : 0,
    'atualizado_em': _local(remota['updated_at'] as String),
  };

  Future<void> _marcarNoServidor(DatabaseExecutor txn, int id) => txn.update(
    'registros_erro',
    {'no_servidor': 1},
    where: 'id = ?',
    whereArgs: [id],
  );

  // O caderno grava datas locais sem fuso (ver RegistroErro.toMap); o
  // servidor guarda timestamptz. A conversão mantém a ordenação por texto.
  static String _utc(String local) =>
      DateTime.parse(local).toUtc().toIso8601String();
  static String _local(String utc) =>
      DateTime.parse(utc).toLocal().toIso8601String();
}

class _Contagem {
  int alterados = 0;
  int excluidos = 0;
}

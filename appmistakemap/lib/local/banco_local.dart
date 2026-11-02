import 'package:sqflite/sqflite.dart';

import 'fabrica_banco.dart';

/// Banco SQLite do aparelho: caderno de erros (v1), desde a v2 o cache
/// offline do Supabase e a fila de envio (ver lib/sync/) e, desde a v3, o
/// estado da sincronização do caderno com a tabela `error_notes`.
///
/// O esquema está documentado em BANCO_LOCAL.md. Mudanças de esquema sobem
/// [versao] e entram em `onUpgrade`, nunca reescrevendo o `onCreate`.
class BancoLocal {
  BancoLocal({this.fabrica, this.caminho});

  /// Instância usada pelo app; os testes criam a sua com banco em memória.
  static final BancoLocal instancia = BancoLocal();

  static const String nomeArquivo = 'mistakemap_local.db';
  static const int versao = 3;

  /// Nulo usa a fábrica da plataforma (ver fabrica_banco.dart).
  final DatabaseFactory? fabrica;

  /// Nulo usa [nomeArquivo] na pasta de bancos do aparelho.
  final String? caminho;
  Future<Database>? _abrindo;

  /// Abre o banco uma única vez; chamadas seguintes reaproveitam a conexão.
  Future<Database> get banco => _abrindo ??= _abrir();

  Future<Database> _abrir() async {
    final f = fabrica ?? fabricaDoBanco();
    return f.openDatabase(
      caminho ?? await caminhoDoBanco(f, nomeArquivo),
      options: OpenDatabaseOptions(
        version: versao,
        // O SQLite só aplica FOREIGN KEY com esta pragma ligada por conexão.
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, versao) async {
          await criarTabelas(db, versao);
          await criarTabelasSincronizacao(db);
          await sincronizarCaderno(db);
        },
        onUpgrade: (db, de, para) async {
          if (de < 2) await criarTabelasSincronizacao(db);
          if (de < 3) await sincronizarCaderno(db);
        },
      ),
    );
  }

  /// DDL da versão 1 (ver BANCO_LOCAL.md).
  static Future<void> criarTabelas(Database db, int versao) async {
    final lote = db.batch();
    lote.execute('''
      CREATE TABLE disciplinas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id TEXT NOT NULL,
        nome TEXT NOT NULL,
        UNIQUE (usuario_id, nome)
      )
    ''');
    lote.execute('''
      CREATE TABLE registros_erro (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id TEXT NOT NULL,
        disciplina_id INTEGER NOT NULL
          REFERENCES disciplinas (id) ON DELETE CASCADE,
        titulo TEXT NOT NULL,
        descricao TEXT NOT NULL,
        tipo_erro TEXT NOT NULL CHECK (tipo_erro IN
          ('conceitual', 'calculo', 'interpretacao', 'atencao')),
        revisado INTEGER NOT NULL DEFAULT 0 CHECK (revisado IN (0, 1)),
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL
      )
    ''');
    lote.execute(
      'CREATE INDEX idx_registros_usuario '
      'ON registros_erro (usuario_id, atualizado_em)',
    );
    lote.execute(
      'CREATE INDEX idx_registros_disciplina ON registros_erro (disciplina_id)',
    );
    await lote.commit(noResult: true);
  }

  /// DDL da versão 2: cache das consultas ao Supabase e fila de envio.
  static Future<void> criarTabelasSincronizacao(Database db) async {
    final lote = db.batch();
    // Última resposta do Supabase para cada tela, em JSON, por usuário.
    lote.execute('''
      CREATE TABLE cache_consultas (
        usuario_id TEXT NOT NULL,
        chave TEXT NOT NULL,
        dados TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        PRIMARY KEY (usuario_id, chave)
      )
    ''');
    // Alterações feitas sem rede, enviadas em ordem quando ela volta.
    lote.execute('''
      CREATE TABLE fila_sync (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id TEXT NOT NULL,
        operacao TEXT NOT NULL CHECK (operacao IN
          ('criar_tentativa', 'enviar_foto', 'editar_exercicio',
           'excluir_exercicio')),
        dados TEXT NOT NULL,
        imagem BLOB,
        situacao TEXT NOT NULL DEFAULT 'pendente'
          CHECK (situacao IN ('pendente', 'erro')),
        tentativas INTEGER NOT NULL DEFAULT 0,
        ultimo_erro TEXT,
        criado_em TEXT NOT NULL
      )
    ''');
    lote.execute('CREATE INDEX idx_fila_usuario ON fila_sync (usuario_id, id)');
    await lote.commit(noResult: true);
  }

  /// DDL da versão 3: o caderno passa a sincronizar com o Supabase.
  ///
  /// * `uid`: id do registro no servidor (uuid), igual em todos os aparelhos.
  /// * `pendente`: 1 enquanto a última alteração não subiu.
  /// * `no_servidor`: 1 depois que o servidor confirmou o registro; um
  ///   registro que nunca subiu é apagado de vez, sem tombstone.
  /// * `excluido_em`: tombstone local. A linha some da tela na hora e só sai
  ///   do banco depois que a exclusão chegou ao servidor.
  ///
  /// `estado_sync` guarda os cursores da leitura incremental, por usuário.
  static Future<void> sincronizarCaderno(Database db) async {
    final lote = db.batch();
    lote.execute('ALTER TABLE registros_erro ADD COLUMN uid TEXT');
    lote.execute(
      'ALTER TABLE registros_erro '
      'ADD COLUMN pendente INTEGER NOT NULL DEFAULT 1',
    );
    lote.execute(
      'ALTER TABLE registros_erro '
      'ADD COLUMN no_servidor INTEGER NOT NULL DEFAULT 0',
    );
    lote.execute('ALTER TABLE registros_erro ADD COLUMN excluido_em TEXT');
    // Registros anteriores ganham um UUID v4 e sobem na primeira sincronização.
    lote.execute('''
      UPDATE registros_erro SET uid =
        lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' ||
        substr(lower(hex(randomblob(2))), 2) || '-' ||
        substr('89ab', 1 + (abs(random()) % 4), 1) ||
        substr(lower(hex(randomblob(2))), 2) || '-' ||
        lower(hex(randomblob(6)))
      WHERE uid IS NULL
    ''');
    lote.execute(
      'CREATE UNIQUE INDEX idx_registros_uid ON registros_erro (uid)',
    );
    lote.execute(
      'CREATE INDEX idx_registros_pendentes '
      'ON registros_erro (usuario_id, pendente)',
    );
    lote.execute('''
      CREATE TABLE estado_sync (
        usuario_id TEXT NOT NULL,
        chave TEXT NOT NULL,
        valor TEXT NOT NULL,
        PRIMARY KEY (usuario_id, chave)
      )
    ''');
    await lote.commit(noResult: true);
  }

  Future<void> fechar() async {
    final aberto = _abrindo;
    _abrindo = null;
    if (aberto != null) await (await aberto).close();
  }
}

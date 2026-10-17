import 'package:sqflite/sqflite.dart';

import 'fabrica_banco.dart';

/// Banco SQLite do caderno de erros, guardado no próprio aparelho.
///
/// O esquema está documentado em BANCO_LOCAL.md. Mudanças de esquema sobem
/// [versao] e entram em `onUpgrade`, nunca reescrevendo o `onCreate`.
class BancoLocal {
  BancoLocal({this.fabrica, this.caminho});

  /// Instância usada pelo app; os testes criam a sua com banco em memória.
  static final BancoLocal instancia = BancoLocal();

  static const String nomeArquivo = 'mistakemap_local.db';
  static const int versao = 1;

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
        onCreate: criarTabelas,
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

  Future<void> fechar() async {
    final aberto = _abrindo;
    _abrindo = null;
    if (aberto != null) await (await aberto).close();
  }
}

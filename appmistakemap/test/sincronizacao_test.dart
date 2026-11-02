import 'dart:convert';
import 'dart:io' show Directory;
import 'dart:typed_data';

import 'package:appmistakemap/ai/analysis_repository.dart' show AnalysisFailure;
import 'package:appmistakemap/local/banco_local.dart';
import 'package:appmistakemap/local/registro_erro.dart';
import 'package:appmistakemap/local/registro_erro_dao.dart';
import 'package:appmistakemap/sync/armazem_sync.dart';
import 'package:appmistakemap/sync/conexao.dart';
import 'package:appmistakemap/sync/remoto_supabase.dart';
import 'package:appmistakemap/sync/remoto_sync.dart';
import 'package:appmistakemap/sync/sincronizador.dart';
import 'package:appmistakemap/sync/sobreposicao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' show join;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _usuario = '11111111-1111-4111-8111-111111111111';
final _semRede = http.ClientException('Failed host lookup');

// JPEG mínimo: a assinatura basta para imageContentType.
final _foto = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

/// Servidor falso: registra as chamadas e falha quando mandado.
class _RemotoFalso implements RemotoSync {
  final chamadas = <String>[];
  final criadas = <Map<String, Object?>>[];
  final fotos = <Uint8List?>[];
  Object? falha;
  bool sondaOk = true;

  Future<void> _registrar(String chamada) async {
    chamadas.add(chamada);
    final erro = falha;
    if (erro != null) throw erro;
  }

  @override
  Future<void> criarTentativa(
    String usuarioId,
    Map<String, Object?> dados,
    Uint8List? imagem,
  ) async {
    await _registrar('criar');
    criadas.add(dados);
    fotos.add(imagem);
  }

  @override
  Future<void> enviarFoto(String tentativaId, Uint8List imagem) =>
      _registrar('foto:$tentativaId');

  @override
  Future<void> editarExercicio(
    String usuarioId, {
    required String exercicioId,
    required String materiaIdAtual,
    required String materiaAtual,
    required String novaMateria,
    required String novoEnunciado,
  }) => _registrar('editar:$exercicioId');

  @override
  Future<void> excluirExercicio(
    String usuarioId, {
    required String exercicioId,
    required String materiaId,
    String? tentativaId,
  }) => _registrar('excluir:$exercicioId');

  @override
  Future<void> analisar(String tentativaId) async =>
      chamadas.add('analisar:$tentativaId');

  @override
  Future<void> sondar() async {
    if (!sondaOk) throw _semRede;
  }

  @override
  void Function() ouvirAlteracoes(String usuarioId, void Function() aoMudar) =>
      () {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late BancoLocal banco;
  late Sincronizador sync;
  late _RemotoFalso remoto;

  setUp(() {
    banco = BancoLocal(
      fabrica: databaseFactoryFfiNoIsolate,
      caminho: inMemoryDatabasePath,
    );
    sync = Sincronizador(banco: banco, habilitado: true);
    remoto = _RemotoFalso();
  });

  tearDown(() async {
    sync.parar();
    await banco.fechar();
  });

  Future<void> iniciar() async {
    sync.iniciar(_usuario, remoto);
    await sync.sincronizar();
  }

  group('conexão', () {
    test('só falta de rede conta como offline', () {
      expect(ehFalhaDeRede(_semRede), isTrue);
      expect(ehFalhaDeRede(const FunctionException(status: 0)), isTrue);
      expect(ehFalhaDeRede(const PostgrestException(message: 'rls')), isFalse);
      expect(ehFalhaDeRede(const FunctionException(status: 500)), isFalse);
      // upload-url/analyze-attempt sem rede chegam traduzidos por _invoke.
      expect(ehFalhaDeRede(const AnalysisFailure('x', network: true)), isTrue);
      expect(ehFalhaDeRede(const AnalysisFailure('cota')), isFalse);
    });

    test('novoUuid gera UUID v4 diferentes', () {
      final a = novoUuid();
      expect(
        a,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(novoUuid(), isNot(a));
    });
  });

  group('consultar', () {
    test('com rede devolve o Supabase e guarda no SQLite', () async {
      await iniciar();
      final dados = await sync.consultar(_usuario, 'lista', () async {
        return [
          {'id': 'a'},
        ];
      });
      expect(dados, [
        {'id': 'a'},
      ]);
      expect(sync.online.value, isTrue);

      // Sem rede, a mesma chave volta do cache.
      final offline = await sync.consultar(
        _usuario,
        'lista',
        () async => throw _semRede,
      );
      expect(offline, [
        {'id': 'a'},
      ]);
      expect(sync.online.value, isFalse);
    });

    test('sem rede e sem cache repassa o erro', () async {
      await iniciar();
      await expectLater(
        sync.consultar(_usuario, 'nunca', () async => throw _semRede),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('erro do servidor não cai no cache', () async {
      await iniciar();
      await sync.consultar(_usuario, 'lista', () async => ['velho']);
      await expectLater(
        sync.consultar(
          _usuario,
          'lista',
          () async => throw const PostgrestException(message: 'rls'),
        ),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('o cache de um usuário não aparece para outro', () async {
      await iniciar();
      await sync.consultar(_usuario, 'lista', () async => ['meu']);
      await expectLater(
        sync.consultar('outro', 'lista', () async => throw _semRede),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('desabilitado vai direto ao servidor', () async {
      final direto = Sincronizador(banco: banco, habilitado: false);
      await expectLater(
        direto.consultar(_usuario, 'x', () async => throw _semRede),
        throwsA(isA<http.ClientException>()),
      );
      expect(await direto.fila(_usuario), isEmpty);
    });
  });

  group('fila offline', () {
    Future<void> enfileirarComFoto() => sync.enfileirarTentativa(
      usuarioId: _usuario,
      materia: 'Equações',
      enunciado: 'Resolver 2x + 3 = 7',
      resposta: 'x = 5',
      dificuldade: 'sinal',
      imagem: _foto,
    );

    test(
      'guarda a submissão com ids do aparelho e envia ao reconectar',
      () async {
        remoto.falha = _semRede;
        await iniciar();
        await enfileirarComFoto();
        expect(sync.pendentes.value, 1);

        final fila = await sync.fila(_usuario);
        expect(fila.single.operacao, OperacaoFila.criarTentativa);
        expect(fila.single.dados['subject'], 'Equações');
        expect(fila.single.exercicioId, hasLength(36));

        // Ainda sem rede: a operação fica e conta a tentativa.
        await sync.sincronizar();
        expect(sync.online.value, isFalse);
        expect((await sync.fila(_usuario)).single.tentativas, 1);

        remoto.falha = null;
        final antes = sync.alteracoes.value;
        await sync.sincronizar();
        expect(remoto.criadas.single['attempt_id'], fila.single.tentativaId);
        expect(remoto.fotos.single, _foto);
        expect(await sync.fila(_usuario), isEmpty);
        expect(sync.pendentes.value, 0);
        expect(sync.online.value, isTrue);
        expect(sync.alteracoes.value, greaterThan(antes));
        await pumpEventQueue();
        expect(
          remoto.chamadas,
          contains('analisar:${fila.single.tentativaId}'),
        );
      },
    );

    test('envia em ordem e para na primeira queda de rede', () async {
      await iniciar();
      await enfileirarComFoto();
      await sync.enfileirarTentativa(
        usuarioId: _usuario,
        materia: 'Geometria',
        enunciado: 'Área do círculo',
        resposta: 'pi r',
        dificuldade: '',
      );
      remoto.falha = _semRede;
      await sync.sincronizar();
      expect(remoto.chamadas.where((c) => c == 'criar'), hasLength(1));
      expect(await sync.fila(_usuario), hasLength(2));
    });

    test('foto pendente de tentativa já criada vira enviar_foto', () async {
      await iniciar();
      await sync.enfileirarTentativa(
        usuarioId: _usuario,
        materia: 'Equações',
        enunciado: 'x',
        resposta: 'y',
        dificuldade: '',
        imagem: _foto,
        tentativaId: 'attempt-servidor',
      );
      await sync.sincronizar();
      expect(remoto.chamadas, contains('foto:attempt-servidor'));
    });

    test('edição recusada por já ter análise fica preservada', () async {
      await iniciar();
      remoto.falha = _semRede;
      final resultado = await sync.editarExercicio(
        usuarioId: _usuario,
        exercicioId: 'ex-1',
        materiaIdAtual: 'sub-1',
        materiaAtual: 'Equações',
        novaMateria: 'Equações',
        novoEnunciado: 'novo',
      );
      expect(resultado, ResultadoEscrita.naFila);

      remoto.falha = const PostgrestException(
        message: 'create a new exercise to change a submitted prompt',
        code: '42501',
      );
      await sync.sincronizar();
      final fila = await sync.fila(_usuario);
      expect(fila.single.comErro, isTrue);
      expect(fila.single.dados['prompt'], 'novo');
      expect(sync.aviso.value, contains('preservada'));
    });

    test('outra recusa fica marcada como erro e não repete', () async {
      await iniciar();
      remoto.falha = _semRede;
      await sync.excluirExercicio(
        usuarioId: _usuario,
        exercicioId: 'ex-1',
        materiaId: 'sub-1',
      );
      remoto.falha = const PostgrestException(message: 'proibido');
      await sync.sincronizar();
      final fila = await sync.fila(_usuario);
      expect(fila.single.comErro, isTrue);
      expect(fila.single.ultimoErro, 'proibido');
      expect(sync.aviso.value, contains('proibido'));

      remoto.chamadas.clear();
      await sync.sincronizar();
      expect(remoto.chamadas, isEmpty);

      await sync.descartar(fila.single);
      expect(await sync.fila(_usuario), isEmpty);
    });

    test('excluir algo criado offline só limpa a fila', () async {
      remoto.falha = _semRede;
      await iniciar();
      await enfileirarComFoto();
      final criado = (await sync.fila(_usuario)).single;
      final resultado = await sync.excluirExercicio(
        usuarioId: _usuario,
        exercicioId: criado.exercicioId!,
        materiaId: '${prefixoMateriaLocal}Equações',
        tentativaId: criado.tentativaId,
      );
      expect(resultado, ResultadoEscrita.enviado);
      expect(await sync.fila(_usuario), isEmpty);
      expect(remoto.chamadas.where((c) => c.startsWith('excluir')), isEmpty);
    });

    test('enfileirar agenda o envio mesmo sem consulta offline', () async {
      await iniciar();
      expect(sync.online.value, isTrue);
      await enfileirarComFoto();
      expect(sync.online.value, isFalse);
    });

    test('criação enviada em parte também é excluída no servidor', () async {
      await iniciar();
      await enfileirarComFoto();
      remoto.falha = _semRede;
      await sync.sincronizar(); // caiu no meio: tentativas = 1
      final criado = (await sync.fila(_usuario)).single;
      expect(criado.tentativas, 1);

      final resultado = await sync.excluirExercicio(
        usuarioId: _usuario,
        exercicioId: criado.exercicioId!,
        materiaId: '${prefixoMateriaLocal}Equações',
        tentativaId: criado.tentativaId,
      );
      // Ainda offline: a criação sai e a exclusão espera a rede.
      expect(resultado, ResultadoEscrita.naFila);
      final fila = await sync.fila(_usuario);
      expect(fila.single.operacao, OperacaoFila.excluirExercicio);
      expect(fila.single.exercicioId, criado.exercicioId);
    });

    test('com rede a exclusão vai direto ao servidor', () async {
      await iniciar();
      final resultado = await sync.excluirExercicio(
        usuarioId: _usuario,
        exercicioId: 'ex-9',
        materiaId: 'sub-1',
      );
      expect(resultado, ResultadoEscrita.enviado);
      expect(remoto.chamadas, ['excluir:ex-9']);
      expect(await sync.fila(_usuario), isEmpty);
    });
  });

  group('sobreposição da fila', () {
    OperacaoFila op(String operacao, Map<String, Object?> dados) =>
        OperacaoFila(
          usuarioId: _usuario,
          operacao: operacao,
          dados: dados,
          criadoEm: DateTime.utc(2026, 10, 27),
        );

    test('operações recusadas preservam os dados do servidor', () {
      final recusadas = [
        OperacaoFila(
          usuarioId: _usuario,
          operacao: OperacaoFila.editarExercicio,
          dados: {'exercise_id': 'ex-1', 'subject': 'Outra', 'prompt': 'local'},
          situacao: 'erro',
          criadoEm: DateTime.utc(2026),
        ),
        OperacaoFila(
          usuarioId: _usuario,
          operacao: OperacaoFila.excluirExercicio,
          dados: {'exercise_id': 'ex-1'},
          situacao: 'erro',
          criadoEm: DateTime.utc(2026),
        ),
      ];
      final resultado = sobreporExercicios(
        [
          {'id': 'sub-1', 'name': 'Física'},
        ],
        [
          {'id': 'ex-1', 'subject_id': 'sub-1', 'prompt_text': 'servidor'},
        ],
        recusadas,
        _usuario,
      );
      expect(resultado.exercicios.single['prompt_text'], 'servidor');
      expect(
        sobreporTentativas([
          {'id': 'a', 'exercise_id': 'ex-1'},
        ], recusadas),
        hasLength(1),
      );
    });

    test('mostra criação, edição e exclusão feitas offline', () {
      final r = sobreporExercicios(
        [
          {'id': 'sub-1', 'name': 'Equações'},
        ],
        [
          {
            'id': 'ex-1',
            'subject_id': 'sub-1',
            'prompt_text': 'antigo',
            'attempts': <Object>[],
          },
          {
            'id': 'ex-2',
            'subject_id': 'sub-1',
            'prompt_text': 'some',
            'attempts': <Object>[],
          },
        ],
        [
          op(OperacaoFila.criarTentativa, {
            'exercise_id': 'ex-novo',
            'attempt_id': 'at-novo',
            'subject': 'Geometria',
            'prompt': 'Área',
            'criado_em': '2026-10-27T00:00:00.000Z',
          }),
          op(OperacaoFila.editarExercicio, {
            'exercise_id': 'ex-1',
            'subject': 'Equações',
            'prompt': 'novo',
          }),
          op(OperacaoFila.excluirExercicio, {'exercise_id': 'ex-2'}),
        ],
        _usuario,
      );
      expect(r.exercicios.map((e) => e['id']), ['ex-novo', 'ex-1']);
      expect(
        r.exercicios.first['subject_id'],
        '${prefixoMateriaLocal}Geometria',
      );
      expect(
        (r.exercicios.first['attempts'] as List).single['status'],
        statusOffline,
      );
      expect(r.exercicios.last['prompt_text'], 'novo');
      expect(r.materias.map((m) => m['name']), ['Equações', 'Geometria']);
    });

    test('tentativa de prática entra no exercício que já existe', () {
      final r = sobreporExercicios(
        [
          {'id': 'sub-1', 'name': 'Equações'},
        ],
        [
          {
            'id': 'ex-p',
            'subject_id': 'sub-1',
            'prompt_text': 'p',
            'attempts': <Object>[],
          },
        ],
        [
          op(OperacaoFila.criarTentativa, {
            'exercise_id': 'ex-p',
            'attempt_id': 'at-1',
            'pratica': true,
            'subject': 'Equações',
            'prompt': 'p',
            'criado_em': '2026-10-27T00:00:00.000Z',
          }),
        ],
        _usuario,
      );
      expect(r.exercicios, hasLength(1));
      expect((r.exercicios.single['attempts'] as List).single['id'], 'at-1');
    });

    test('contagem do Início soma as pendentes e tira as excluídas', () {
      final linhas = sobreporTentativas(
        [
          {'id': 'a', 'status': 'completed', 'exercise_id': 'ex-1'},
          {'id': 'b', 'status': 'pending', 'exercise_id': 'ex-2'},
        ],
        [
          op(OperacaoFila.excluirExercicio, {'exercise_id': 'ex-2'}),
          op(OperacaoFila.criarTentativa, {
            'exercise_id': 'ex-3',
            'attempt_id': 'c',
          }),
        ],
      );
      expect(linhas.map((l) => l['status']), ['completed', statusOffline]);
    });
  });

  test('a versão 2 do banco preserva o caderno da versão 1', () async {
    final pasta = await Directory.systemTemp.createTemp('mistakemap_v1_');
    addTearDown(() => pasta.delete(recursive: true));
    final arquivo = join(pasta.path, 'v1.db');
    final v1 = await databaseFactoryFfiNoIsolate.openDatabase(
      arquivo,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: BancoLocal.criarTabelas,
      ),
    );
    await v1.close();

    final antigo = BancoLocal(
      fabrica: databaseFactoryFfiNoIsolate,
      caminho: arquivo,
    );
    // Abre já na v2 e grava no caderno e na fila.
    final dao = RegistroErroDao(antigo);
    final data = DateTime(2026, 10, 27);
    await dao.inserir(
      RegistroErro(
        usuarioId: _usuario,
        disciplina: 'Física',
        titulo: 'Unidade',
        descricao: 'Esqueci de converter km/h.',
        tipo: TipoErro.calculo,
        criadoEm: data,
        atualizadoEm: data,
      ),
    );
    final armazem = ArmazemSync(antigo);
    await armazem.gravarCache(_usuario, 'x', {'ok': true});
    expect((await armazem.lerCache(_usuario, 'x'))!.dados, {'ok': true});
    expect(await (await antigo.banco).getVersion(), 2);
    expect(await dao.listar(_usuario), hasLength(1));
    await antigo.fechar();
  });

  group('RemotoSupabase', () {
    test('cria exercício e tentativa sem duplicar em reenvios', () async {
      final requisicoes = <http.Request>[];
      final client = SupabaseClient(
        'https://sync-tests.invalid',
        'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requisicoes.add(request);
          final corpo = switch ((request.method, request.url.path)) {
            ('GET', '/rest/v1/subjects') => '[{"id":"sub-1"}]',
            _ => '',
          };
          return http.Response(
            corpo,
            corpo.isEmpty ? 201 : 200,
            headers: {'content-type': 'application/json; charset=utf-8'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await RemotoSupabase(client).criarTentativa(_usuario, {
        'exercise_id': 'ex-1',
        'attempt_id': 'at-1',
        'subject': 'Equações',
        'prompt': 'Resolver',
        'answer': 'x = 2',
        'difficulty': '',
        'criado_em': '2026-10-27T00:00:00.000Z',
      }, null);

      final escritas = requisicoes.where((r) => r.method == 'POST').toList();
      expect(escritas.map((r) => r.url.path), [
        '/rest/v1/exercises',
        '/rest/v1/attempts',
      ]);
      for (final r in escritas) {
        expect(r.headers['Prefer'], contains('resolution=ignore-duplicates'));
      }
      final tentativa = jsonDecode(escritas.last.body) as Map;
      expect(tentativa['id'], 'at-1');
      expect(tentativa['status'], 'pending');
      expect(tentativa['attempted_at'], '2026-10-27T00:00:00.000Z');
    });
  });
}

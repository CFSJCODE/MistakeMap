import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../ai/analysis_repository.dart'
    show AnalysisFailure, notifyAnalysisChanged;
import '../local/banco_local.dart';
import '../local/fabrica_banco.dart' show executandoTestes;
import 'armazem_sync.dart';
import 'conexao.dart';
import 'remoto_sync.dart';

/// Resultado de uma alteração pedida pela tela.
enum ResultadoEscrita {
  /// Já está no Supabase.
  enviado,

  /// Ficou na fila do aparelho e sobe quando a rede voltar.
  naFila,
}

/// Mantém o app "Supabase primeiro, banco local depois":
///
/// * [consultar] tenta o Supabase; com sucesso grava a resposta no SQLite,
///   sem rede devolve a última resposta gravada.
/// * Alterações sem rede entram em `fila_sync` e são enviadas em ordem quando
///   a conexão volta (sonda periódica, retorno do app ao primeiro plano ou
///   qualquer consulta que volte a funcionar).
/// * O Supabase Realtime avisa quando a IA muda uma tentativa, e as telas
///   recarregam ouvindo [alteracoes].
///
/// Conflitos: o servidor manda no status e na análise. Uma alteração que o
/// servidor recusa (exercício já analisado, por exemplo) sai da fila e vira
/// [aviso]; nada é sobrescrito no Supabase com dados velhos do aparelho.
class Sincronizador {
  Sincronizador({BancoLocal? banco, bool? habilitado})
    : _armazem = ArmazemSync(banco ?? BancoLocal.instancia),
      habilitado = habilitado ?? !executandoTestes();

  /// Instância do app. Dentro do `flutter test` nasce desabilitada: as
  /// consultas vão direto ao servidor falso e nada é gravado no disco.
  static Sincronizador instancia = Sincronizador();

  final bool habilitado;
  final ArmazemSync _armazem;

  /// Tempo máximo de uma consulta antes de cair no cache.
  static const limiteConsulta = Duration(seconds: 12);
  static const _intervaloInicial = Duration(seconds: 5);
  static const _intervaloMaximo = Duration(minutes: 1);

  final online = ValueNotifier<bool>(true);

  /// Muda quando os dados do servidor mudaram (fila enviada ou Realtime).
  final alteracoes = ValueNotifier<int>(0);

  /// Operações da fila do usuário atual, pendentes ou com erro.
  final pendentes = ValueNotifier<int>(0);

  /// Última mensagem de conflito ou recusa, para a tela mostrar uma vez.
  final aviso = ValueNotifier<String?>(null);

  RemotoSync? _remoto;
  String? _usuarioId;
  Timer? _sonda;
  Timer? _debounce;
  Duration _intervalo = _intervaloInicial;
  void Function()? _cancelarRealtime;
  AppLifecycleListener? _ciclo;
  Future<void>? _enviando;

  String? get usuarioId => _usuarioId;

  void iniciar(String usuarioId, RemotoSync remoto) {
    if (_usuarioId == usuarioId && identical(_remoto, remoto)) return;
    parar();
    _usuarioId = usuarioId;
    _remoto = remoto;
    if (!habilitado) return;
    try {
      _cancelarRealtime = remoto.ouvirAlteracoes(usuarioId, _alteracaoRemota);
    } catch (_) {
      // Sem Realtime o app continua: a sonda e as recargas cobrem.
    }
    _ciclo = AppLifecycleListener(onResume: () => unawaited(sincronizar()));
    unawaited(_contarPendentes());
    unawaited(sincronizar());
  }

  void parar() {
    _sonda?.cancel();
    _debounce?.cancel();
    _sonda = _debounce = null;
    _ciclo?.dispose();
    _ciclo = null;
    final cancelar = _cancelarRealtime;
    _cancelarRealtime = null;
    if (cancelar != null) {
      try {
        cancelar();
      } catch (_) {
        // O canal pode já ter caído junto com a rede.
      }
    }
    _usuarioId = null;
    _remoto = null;
    online.value = true;
    pendentes.value = 0;
  }

  // ─── Leitura: Supabase primeiro, SQLite como reserva ──────────────────────

  /// Executa [remoto] e guarda o resultado (JSON) em [chave]. Sem rede,
  /// devolve o último resultado guardado; sem cache, repassa o erro.
  Future<Object?> consultar(
    String usuarioId,
    String chave,
    Future<Object?> Function() remoto,
  ) async {
    if (!habilitado) return remoto();
    try {
      final dados = await remoto().timeout(limiteConsulta);
      _ficarOnline();
      try {
        await _armazem.gravarCache(usuarioId, chave, dados);
      } catch (_) {
        // Cache é reserva: falhar ao gravar não pode esconder dados frescos.
      }
      return dados;
    } catch (erro) {
      if (!ehFalhaDeRede(erro)) rethrow;
      _ficarOffline();
      final salvo = await _lerCache(usuarioId, chave);
      if (salvo == null) rethrow;
      return salvo.dados;
    }
  }

  Future<({Object? dados, DateTime quando})?> _lerCache(
    String usuarioId,
    String chave,
  ) async {
    try {
      return await _armazem.lerCache(usuarioId, chave);
    } catch (_) {
      return null;
    }
  }

  /// Fila do usuário (sem fotos) para as telas mostrarem o que ainda não
  /// subiu. Vazia quando desabilitado ou se o SQLite falhar.
  Future<List<OperacaoFila>> fila(String usuarioId) async {
    if (!habilitado) return const [];
    try {
      return await _armazem.fila(usuarioId);
    } catch (_) {
      return const [];
    }
  }

  // ─── Escrita: tenta o servidor, sem rede vai para a fila ──────────────────

  /// Guarda uma submissão feita sem rede. Com [tentativaId], a tentativa já
  /// existe no servidor e só falta a foto.
  Future<void> enfileirarTentativa({
    required String usuarioId,
    required String materia,
    required String enunciado,
    required String resposta,
    required String dificuldade,
    Uint8List? imagem,
    String? exercicioPraticaId,
    String? tentativaId,
  }) async {
    if (!habilitado) {
      throw StateError('Fila offline indisponível neste ambiente.');
    }
    final agora = DateTime.now().toUtc();
    if (tentativaId != null) {
      if (imagem == null) return;
      await _armazem.enfileirar(
        OperacaoFila(
          usuarioId: usuarioId,
          operacao: OperacaoFila.enviarFoto,
          dados: {'attempt_id': tentativaId},
          imagem: imagem,
          criadoEm: agora,
        ),
      );
    } else {
      await _armazem.enfileirar(
        OperacaoFila(
          usuarioId: usuarioId,
          operacao: OperacaoFila.criarTentativa,
          dados: {
            'exercise_id': exercicioPraticaId ?? novoUuid(),
            'attempt_id': novoUuid(),
            'pratica': exercicioPraticaId != null,
            'subject': materia,
            'prompt': enunciado,
            'answer': resposta,
            'difficulty': dificuldade,
            'criado_em': agora.toIso8601String(),
          },
          imagem: imagem,
          criadoEm: agora,
        ),
      );
    }
    await _depoisDeEnfileirar();
    // A submissão só chega aqui depois de uma falha de rede: a sonda agenda
    // o envio mesmo que nenhuma consulta tenha marcado o app como offline.
    _ficarOffline();
  }

  Future<ResultadoEscrita> excluirExercicio({
    required String usuarioId,
    required String exercicioId,
    required String materiaId,
    String? tentativaId,
  }) async {
    final remoto = _remoto;
    if (habilitado) {
      // Um envio em andamento pode estar criando este exercício agora.
      await _enviando;
      // Criado sem rede e ainda na fila: excluir é só tirar da fila.
      final fila = await this.fila(usuarioId);
      final criacao = fila
          .where(
            (op) =>
                op.operacao == OperacaoFila.criarTentativa &&
                op.exercicioId == exercicioId,
          )
          .firstOrNull;
      if (criacao != null) {
        await _armazem.remover(criacao.id!);
        for (final op in fila) {
          if (op.operacao == OperacaoFila.enviarFoto &&
              op.tentativaId == criacao.tentativaId) {
            await _armazem.remover(op.id!);
          }
        }
        // Sem nenhuma tentativa de envio, nada chegou ao servidor. Depois de
        // uma, exercício e tentativa podem já existir lá (a queda pode ter
        // sido na foto), então a exclusão segue para o Supabase também.
        if (criacao.dados['pratica'] != true && criacao.tentativas == 0) {
          await _depoisDeEnfileirar();
          return ResultadoEscrita.enviado;
        }
      }
    }
    final dados = <String, Object?>{
      'exercise_id': exercicioId,
      'subject_id': materiaId,
      'attempt_id': tentativaId,
    };
    return _escrever(
      usuarioId,
      OperacaoFila.excluirExercicio,
      dados,
      () => remoto!.excluirExercicio(
        usuarioId,
        exercicioId: exercicioId,
        materiaId: materiaId,
        tentativaId: tentativaId,
      ),
    );
  }

  Future<ResultadoEscrita> editarExercicio({
    required String usuarioId,
    required String exercicioId,
    required String materiaIdAtual,
    required String materiaAtual,
    required String novaMateria,
    required String novoEnunciado,
  }) {
    final remoto = _remoto;
    return _escrever(
      usuarioId,
      OperacaoFila.editarExercicio,
      {
        'exercise_id': exercicioId,
        'subject_id': materiaIdAtual,
        'subject_atual': materiaAtual,
        'subject': novaMateria,
        'prompt': novoEnunciado,
      },
      () => remoto!.editarExercicio(
        usuarioId,
        exercicioId: exercicioId,
        materiaIdAtual: materiaIdAtual,
        materiaAtual: materiaAtual,
        novaMateria: novaMateria,
        novoEnunciado: novoEnunciado,
      ),
    );
  }

  Future<ResultadoEscrita> _escrever(
    String usuarioId,
    String operacao,
    Map<String, Object?> dados,
    Future<void> Function() noServidor,
  ) async {
    // Já sabidamente offline: não espera o tempo limite de novo.
    if (habilitado && !online.value) {
      await _guardar(usuarioId, operacao, dados);
      return ResultadoEscrita.naFila;
    }
    try {
      await noServidor();
      if (habilitado) _ficarOnline();
      return ResultadoEscrita.enviado;
    } catch (erro) {
      if (!habilitado || !ehFalhaDeRede(erro)) rethrow;
      _ficarOffline();
      await _guardar(usuarioId, operacao, dados);
      return ResultadoEscrita.naFila;
    }
  }

  Future<void> _guardar(
    String usuarioId,
    String operacao,
    Map<String, Object?> dados,
  ) async {
    await _armazem.enfileirar(
      OperacaoFila(
        usuarioId: usuarioId,
        operacao: operacao,
        dados: dados,
        criadoEm: DateTime.now().toUtc(),
      ),
    );
    await _depoisDeEnfileirar();
  }

  /// Remove da fila uma operação recusada pelo servidor (botão da tela).
  Future<void> descartar(OperacaoFila operacao) async {
    if (operacao.id == null) return;
    await _armazem.remover(operacao.id!);
    await _depoisDeEnfileirar();
  }

  Future<void> _depoisDeEnfileirar() async {
    await _contarPendentes();
    alteracoes.value++;
  }

  Future<void> _contarPendentes() async {
    final usuario = _usuarioId;
    if (usuario == null) return;
    pendentes.value = (await fila(usuario)).length;
  }

  // ─── Envio da fila ────────────────────────────────────────────────────────

  /// Envia a fila em ordem. Chamadas simultâneas aguardam o mesmo envio.
  Future<void> sincronizar() {
    if (!habilitado || _remoto == null || _usuarioId == null) {
      return Future.value();
    }
    return _enviando ??= _enviarFila().whenComplete(() => _enviando = null);
  }

  Future<void> _enviarFila() async {
    final remoto = _remoto!;
    final usuario = _usuarioId!;
    var mudou = false;
    List<OperacaoFila> fila;
    try {
      fila = await _armazem.fila(usuario, comImagem: true);
    } catch (_) {
      return;
    }
    for (final op in fila.where((op) => !op.comErro)) {
      try {
        await _executar(remoto, usuario, op);
        await _armazem.remover(op.id!);
        mudou = true;
        _ficarOnline();
      } catch (erro) {
        if (ehFalhaDeRede(erro)) {
          await _armazem.registrarFalha(op.id!, erro.toString());
          _ficarOffline();
          break;
        }
        mudou = true;
        await _recusada(op, erro);
      }
    }
    if (fila.isNotEmpty) await _contarPendentes();
    if (mudou) {
      alteracoes.value++;
      notifyAnalysisChanged();
    }
  }

  Future<void> _executar(
    RemotoSync remoto,
    String usuario,
    OperacaoFila op,
  ) async {
    final d = op.dados;
    switch (op.operacao) {
      case OperacaoFila.criarTentativa:
        await remoto.criarTentativa(usuario, d, op.imagem);
        _analisarDepois(remoto, op.tentativaId!);
      case OperacaoFila.enviarFoto:
        await remoto.enviarFoto(op.tentativaId!, op.imagem!);
        _analisarDepois(remoto, op.tentativaId!);
      case OperacaoFila.editarExercicio:
        await remoto.editarExercicio(
          usuario,
          exercicioId: d['exercise_id'] as String,
          materiaIdAtual: d['subject_id'] as String,
          materiaAtual: d['subject_atual'] as String,
          novaMateria: d['subject'] as String,
          novoEnunciado: d['prompt'] as String,
        );
      case OperacaoFila.excluirExercicio:
        await remoto.excluirExercicio(
          usuario,
          exercicioId: d['exercise_id'] as String,
          materiaId: d['subject_id'] as String,
          tentativaId: d['attempt_id'] as String?,
        );
    }
  }

  void _analisarDepois(RemotoSync remoto, String tentativaId) {
    unawaited(
      remoto
          .analisar(tentativaId)
          .then(
            (_) {},
            onError: (Object _) {
              // O pg_cron analisa as tentativas 'pending' que ficarem para trás.
            },
          ),
    );
  }

  Future<void> _recusada(OperacaoFila op, Object erro) async {
    final analisado =
        erro is PostgrestException &&
        erro.code == '42501' &&
        erro.message.contains('create a new exercise');
    if (op.operacao == OperacaoFila.editarExercicio && analisado) {
      // O servidor já tem uma versão analisada: ela vence a edição offline.
      await _armazem.remover(op.id!);
      aviso.value =
          'A edição feita sem internet foi descartada: o exercício já tinha '
          'sido enviado para análise.';
      return;
    }
    final motivo = erro is AnalysisFailure
        ? erro.message
        : erro is PostgrestException
        ? erro.message
        : erro.toString();
    await _armazem.registrarFalha(op.id!, motivo, definitiva: true);
    aviso.value = 'Uma alteração feita sem internet não foi aceita: $motivo';
  }

  // ─── Estado da conexão ────────────────────────────────────────────────────

  void _ficarOnline() {
    _sonda?.cancel();
    _sonda = null;
    _intervalo = _intervaloInicial;
    if (online.value) return;
    online.value = true;
    // Voltou: envia o que ficou guardado e recarrega as telas.
    unawaited(sincronizar().then((_) => alteracoes.value++));
  }

  void _ficarOffline() {
    online.value = false;
    if (_sonda != null || _remoto == null) return;
    _agendarSonda();
  }

  void _agendarSonda() {
    _sonda = Timer(_intervalo, () async {
      _sonda = null;
      final remoto = _remoto;
      if (remoto == null) return;
      try {
        await remoto.sondar().timeout(limiteConsulta);
        _ficarOnline();
      } catch (_) {
        final dobro = _intervalo * 2;
        _intervalo = dobro > _intervaloMaximo ? _intervaloMaximo : dobro;
        if (!online.value && _remoto != null) _agendarSonda();
      }
    });
  }

  void _alteracaoRemota() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      alteracoes.value++;
      notifyAnalysisChanged();
    });
  }
}

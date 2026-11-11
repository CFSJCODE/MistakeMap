part of '../main.dart';

// ─── Primeira análise guiada ─────────────────────────────────────────────────
// Conta nova, sem nenhuma tentativa: o Início oferece uma questão rápida do
// banco e, corrigida, leva direto ao Mapa de erros. A meta é o aluno ver o
// próprio mapa em até 2 minutos. A correção continua na Edge Function
// question-bank (que grava attempt + análise); o app só escolhe qual questão
// abrir primeiro. A RPC seed_example_exercises roda junto, para que
// "Meus exercícios" também não fique vazio.

/// Escolhe a questão que abre a primeira análise: a mais rápida de
/// responder e de corrigir. Prefere múltipla escolha fácil ainda não
/// respondida; dissertativa fica de fora porque depende da IA e pode
/// demorar.
Questao? escolherQuestaoInicial(List<Questao> questoes) {
  final abertas = [
    for (final q in questoes)
      if (q.ultima == null && q.tipo != TipoQuestao.dissertativa) q,
  ];
  int peso(Questao q) =>
      (q.tipo == TipoQuestao.multiplaEscolha ? 0 : 2) +
      (q.dificuldade == 'facil' ? 0 : 1);
  if (abertas.isEmpty) return null;
  // sort é estável: em caso de empate vale a ordem do banco (position).
  return (abertas.toList()..sort((a, b) => peso(a) - peso(b))).first;
}

/// Preferência local "Agora não", por conta e por aparelho.
class PreferenciaPrimeiraAnalise {
  const PreferenciaPrimeiraAnalise();

  static String chave(String usuarioId) =>
      'primeira_analise_dispensada_$usuarioId';

  Future<bool> dispensada(String usuarioId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(chave(usuarioId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispensar(String usuarioId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(chave(usuarioId), true);
    } catch (_) {
      // Sem armazenamento local o cartão só volta na próxima abertura.
    }
  }
}

/// Abre a primeira análise: carrega o banco, escolhe a questão inicial e,
/// depois da correção, o botão "Ver meu mapa de erros" chama [onVerMapa].
/// Com [semear], copia também os exemplos do catálogo (só age em conta sem
/// exercícios; falha aqui não impede a questão).
Future<void> abrirPrimeiraAnalise(
  BuildContext context, {
  required String usuarioId,
  required VoidCallback onVerMapa,
  RepositorioQuestoes? repositorio,
  bool semear = true,
}) async {
  final repo = repositorio ?? RepositorioQuestoesSupabase(_db);
  if (semear) {
    unawaited(
      Future<void>(() async {
        await _db.rpc('seed_example_exercises');
      }).catchError((Object _) {}),
    );
  }
  Questao? questao;
  try {
    questao = escolherQuestaoInicial(await repo.carregar(usuarioId));
  } catch (_) {
    questao = null;
  }
  if (!context.mounted) return;
  final escolhida = questao;
  if (escolhida == null) {
    _avisar(
      context,
      'Não foi possível abrir a questão agora. Verifique a conexão e tente '
      'de novo.',
      erro: true,
    );
    return;
  }
  var verMapa = false;
  await Navigator.of(context).push(
    MistakeMapPageRoute(
      context: context,
      builder: (rota) => TelaResponderQuestao(
        questoes: [escolhida],
        inicial: 0,
        repositorio: repo,
        onVerMapa: () {
          verMapa = true;
          Navigator.of(rota).pop();
        },
      ),
    ),
  );
  if (verMapa) onVerMapa();
}

/// Lugar do cartão no Início: some depois de "Agora não" (guardado no
/// aparelho). Quem decide se a conta é nova é o Início (zero tentativas).
class GuiaPrimeiraAnalise extends StatefulWidget {
  const GuiaPrimeiraAnalise({
    super.key,
    required this.usuarioId,
    required this.onComecar,
    this.preferencia = const PreferenciaPrimeiraAnalise(),
  });

  final String usuarioId;
  final Future<void> Function() onComecar;
  final PreferenciaPrimeiraAnalise preferencia;

  @override
  State<GuiaPrimeiraAnalise> createState() => _GuiaPrimeiraAnaliseState();
}

class _GuiaPrimeiraAnaliseState extends State<GuiaPrimeiraAnalise> {
  bool? _dispensada;
  bool _abrindo = false;

  @override
  void initState() {
    super.initState();
    widget.preferencia.dispensada(widget.usuarioId).then((d) {
      if (mounted) setState(() => _dispensada = d);
    });
  }

  Future<void> _comecar() async {
    setState(() => _abrindo = true);
    try {
      await widget.onComecar();
    } finally {
      if (mounted) setState(() => _abrindo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Enquanto lê a preferência, não pisca o cartão para quem já dispensou.
    if (_dispensada != false) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: CartaoPrimeiraAnalise(
          abrindo: _abrindo,
          onComecar: _comecar,
          onDispensar: () {
            setState(() => _dispensada = true);
            widget.preferencia.dispensar(widget.usuarioId);
          },
        ),
      ),
    );
  }
}

/// Cartão do Início para quem ainda não tem nenhuma tentativa.
class CartaoPrimeiraAnalise extends StatelessWidget {
  const CartaoPrimeiraAnalise({
    super.key,
    required this.onComecar,
    required this.onDispensar,
    this.abrindo = false,
  });

  final VoidCallback onComecar;
  final VoidCallback onDispensar;

  /// Carregando a questão: o botão vira um anel de progresso.
  final bool abrindo;

  @override
  Widget build(BuildContext context) {
    Widget passo(int n, String texto) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MistakeMapDesign.violet.withValues(alpha: .18),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: context.tipo.caption?.copyWith(
                color: MistakeMapDesign.violetInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: context.tipo.body?.copyWith(color: MistakeMapDesign.abyss),
            ),
          ),
        ],
      ),
    );

    return _PainelVidro(
      acento: MistakeMapDesign.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GlassIconTile(
                icon: WindowsIcons.relationship,
                ink: MistakeMapDesign.violetInk,
                accent: MistakeMapDesign.violet,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Pilula(
                      texto: 'Leva 2 minutos',
                      cor: MistakeMapDesign.violetInk,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sua primeira análise',
                      style: context.tipo.subtitle?.copyWith(
                        color: titleBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          passo(1, 'Responda uma questão rápida de tecnologia.'),
          passo(2, 'O MistakeMap corrige e aponta o tipo de erro.'),
          passo(3, 'Veja o seu mapa de erros começar a se formar.'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MistakeMapFilledButton(
                key: const Key('primeira-analise-comecar'),
                style: _estiloBotao(
                  fonte: 14,
                  fundo: kAcento,
                  texto: MistakeMapDesign.abyss,
                ),
                onPressed: abrindo ? null : onComecar,
                child: abrindo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    : const Text('Começar agora'),
              ),
              MistakeMapButton(
                key: const Key('primeira-analise-dispensar'),
                style: _estiloBotao(fonte: 14),
                onPressed: abrindo ? null : onDispensar,
                child: const Text('Agora não'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── fim: Primeira análise guiada ────────────────────────────────────────────

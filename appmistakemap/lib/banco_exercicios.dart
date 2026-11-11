part of 'main.dart';

// ─── Banco de exercícios (aba Exercícios) ─────────────────────────────────────
// Questões de vários tipos que o aluno responde no próprio app. O app só
// recebe o enunciado e os itens públicos; quem corrige é a Edge Function
// question-bank, que guarda o gabarito e leva cada erro para o Mapa
// (lib/exercicios/banco_questoes.dart).

enum _FiltroSituacao { todas, naoRespondidas, paraRevisar, certas }

/// Situação da última resposta, com a mesma linguagem de cor da Lista.
_EstadoTentativa _estadoQuestao(Questao q) {
  final u = q.ultima;
  if (u == null) {
    return const _EstadoTentativa(
      'Não respondida',
      MistakeMapDesign.mist,
      MistakeMapDesign.steel,
      WindowsIcons.edit,
    );
  }
  if (u.correta == null) {
    return const _EstadoTentativa(
      'Aguardando correção',
      MistakeMapDesign.violet,
      MistakeMapDesign.violetInk,
      WindowsIcons.lightbulb,
    );
  }
  if (u.correta!) {
    return const _EstadoTentativa(
      'Acertou',
      MistakeMapDesign.mint,
      MistakeMapDesign.mintInk,
      WindowsIcons.completed,
    );
  }
  final parcial = (u.nota ?? 0) > 0;
  return _EstadoTentativa(
    parcial ? 'Acertou em parte' : 'Errou',
    parcial ? MistakeMapDesign.amber : MistakeMapDesign.coral,
    parcial ? MistakeMapDesign.amberInk : MistakeMapDesign.coralInk,
    WindowsIcons.refresh,
    pedeAcao: true,
  );
}

IconData _iconeTipo(TipoQuestao t) => switch (t) {
  TipoQuestao.multiplaEscolha => WindowsIcons.radio_btn_on,
  TipoQuestao.multiplaSelecao => WindowsIcons.checkbox_composite,
  TipoQuestao.verdadeiroFalso => WindowsIcons.toggle_left,
  TipoQuestao.numerica => WindowsIcons.calculator,
  TipoQuestao.lacuna => WindowsIcons.text_edit,
  TipoQuestao.ordenacao => WindowsIcons.sort,
  TipoQuestao.associacao => WindowsIcons.link,
  TipoQuestao.dissertativa => WindowsIcons.handwriting,
};

/// Lista do banco com filtros por tipo e por situação.
class BancoExercicios extends StatefulWidget {
  const BancoExercicios({
    super.key,
    required this.user,
    required this.cabecalho,
    this.repositorio,
  });

  final AppUser user;

  /// Seletor de seção, no topo da rolagem.
  final Widget cabecalho;
  final RepositorioQuestoes? repositorio;

  @override
  State<BancoExercicios> createState() => BancoExerciciosState();
}

class BancoExerciciosState extends State<BancoExercicios> {
  late final RepositorioQuestoes _repo =
      widget.repositorio ?? RepositorioQuestoesSupabase(_db);
  List<Questao> _questoes = [];
  bool _carregando = true;
  bool _falha = false;
  TipoQuestao? _tipo;
  _FiltroSituacao _situacao = _FiltroSituacao.todas;

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    if (mounted) setState(() => _carregando = true);
    try {
      final lista = await _repo.carregar(widget.user.id);
      if (!mounted) return;
      setState(() {
        _questoes = lista;
        _falha = false;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _falha = true;
        _carregando = false;
      });
    }
  }

  List<Questao> get _filtradas => [
    for (final q in _questoes)
      if ((_tipo == null || q.tipo == _tipo) &&
          switch (_situacao) {
            _FiltroSituacao.todas => true,
            _FiltroSituacao.naoRespondidas => q.ultima == null,
            _FiltroSituacao.paraRevisar => q.ultima?.correta == false,
            _FiltroSituacao.certas => q.ultima?.correta == true,
          })
        q,
  ];

  Future<void> _abrir(List<Questao> lista, int indice) async {
    await Navigator.of(context).push(
      MistakeMapPageRoute(
        context: context,
        builder: (_) => TelaResponderQuestao(
          questoes: lista,
          inicial: indice,
          repositorio: _repo,
        ),
      ),
    );
    await carregar();
  }

  @override
  Widget build(BuildContext context) {
    final filtradas = _filtradas;
    final respondidas = _questoes.where((q) => q.ultima != null).length;
    final certas = _questoes.where((q) => q.ultima?.correta == true).length;
    return _ListaAtualizavel(
      onRefresh: carregar,
      children: [
        widget.cabecalho,
        const SizedBox(height: 16),
        if (_carregando && _questoes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: ProgressRing()),
          )
        else if (_questoes.isEmpty)
          _AvisoBanco(
            texto: _falha
                ? 'Não foi possível carregar os exercícios. Verifique a '
                      'conexão e tente novamente.'
                : 'Nenhum exercício disponível ainda.',
            onTentar: carregar,
          )
        else ...[
          if (_falha)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Sem conexão. Exibindo os exercícios já carregados.'),
            ),
          _ResumoBanco(
            total: _questoes.length,
            respondidas: respondidas,
            certas: certas,
          ),
          const SizedBox(height: 16),
          _rotuloFiltro(context, 'TIPO DE EXERCÍCIO'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChipFiltro(
                key: const Key('filtro-tipo-todos'),
                texto: 'Todos',
                selecionado: _tipo == null,
                onPressed: () => setState(() => _tipo = null),
              ),
              for (final t in TipoQuestao.values)
                _ChipFiltro(
                  key: Key('filtro-tipo-${t.chave}'),
                  texto: t.rotulo,
                  icone: _iconeTipo(t),
                  selecionado: _tipo == t,
                  onPressed: () => setState(() => _tipo = t),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _rotuloFiltro(context, 'SITUAÇÃO'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (f, texto) in const [
                (_FiltroSituacao.todas, 'Todas'),
                (_FiltroSituacao.naoRespondidas, 'Não respondidas'),
                (_FiltroSituacao.paraRevisar, 'Para revisar'),
                (_FiltroSituacao.certas, 'Acertadas'),
              ])
                _ChipFiltro(
                  texto: texto,
                  selecionado: _situacao == f,
                  onPressed: () => setState(() => _situacao = f),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (filtradas.isEmpty)
            _AvisoBanco(
              texto: 'Nenhum exercício com esses filtros.',
              onTentar: () => setState(() {
                _tipo = null;
                _situacao = _FiltroSituacao.todas;
              }),
              acao: 'Limpar filtros',
            )
          else
            for (var i = 0; i < filtradas.length; i++)
              _QuestaoCard(
                questao: filtradas[i],
                onTap: () => _abrir(filtradas, i),
              ),
        ],
      ],
    );
  }

  Widget _rotuloFiltro(BuildContext context, String texto) => Text(
    texto,
    style: context.tipo.caption?.copyWith(
      color: contentBlue,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    ),
  );
}

class _ResumoBanco extends StatelessWidget {
  const _ResumoBanco({
    required this.total,
    required this.respondidas,
    required this.certas,
  });

  final int total;
  final int respondidas;
  final int certas;

  @override
  Widget build(BuildContext context) {
    final progresso = total == 0 ? 0.0 : respondidas / total;
    return _PainelVidro(
      acento: MistakeMapDesign.azure,
      child: Row(
        children: [
          const GlassIconTile(
            icon: WindowsIcons.education,
            ink: MistakeMapDesign.azureInk,
            accent: MistakeMapDesign.azure,
            size: 44,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$respondidas de $total respondidos · $certas certos',
                  style: context.tipo.bodyStrong?.copyWith(color: titleBlue),
                ),
                const SizedBox(height: 4),
                Text(
                  'Responda aqui mesmo. Cada erro vai para o seu Mapa.',
                  style: context.tipo.caption?.copyWith(color: contentBlue),
                ),
                const SizedBox(height: 8),
                ProgressBar(
                  value: progresso * 100,
                  activeColor: MistakeMapDesign.azureInk,
                  backgroundColor: MistakeMapDesign.hairline,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisoBanco extends StatelessWidget {
  const _AvisoBanco({
    required this.texto,
    required this.onTentar,
    this.acao = 'Tentar novamente',
  });

  final String texto;
  final VoidCallback onTentar;
  final String acao;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      children: [
        Text(
          texto,
          textAlign: TextAlign.center,
          style: context.tipo.body?.copyWith(color: contentBlue),
        ),
        const SizedBox(height: 16),
        Button(onPressed: onTentar, child: Text(acao)),
      ],
    ),
  );
}

/// Filtro em pílula: o selecionado usa o botão preenchido do app.
class _ChipFiltro extends StatelessWidget {
  const _ChipFiltro({
    super.key,
    required this.texto,
    required this.selecionado,
    required this.onPressed,
    this.icone,
  });

  final String texto;
  final bool selecionado;
  final VoidCallback onPressed;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    final estilo = _estiloBotao(
      fonte: 13,
      raio: 999,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      fundo: selecionado ? MistakeMapDesign.azure : null,
      texto: selecionado ? MistakeMapDesign.abyss : contentBlue,
    );
    final rotulo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icone != null) ...[Icon(icone, size: 14), const SizedBox(width: 6)],
        Text(texto),
      ],
    );
    return Semantics(
      selected: selecionado,
      button: true,
      child: selecionado
          ? MistakeMapFilledButton(
              style: estilo,
              onPressed: onPressed,
              child: rotulo,
            )
          : MistakeMapButton(
              style: estilo,
              onPressed: onPressed,
              child: rotulo,
            ),
    );
  }
}

class _QuestaoCard extends StatelessWidget {
  const _QuestaoCard({required this.questao, required this.onTap});

  final Questao questao;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final estado = _estadoQuestao(questao);
    final dificuldade = rotulosDificuldade[questao.dificuldade];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _CartaoFluent(
        onPressed: onTap,
        cor: Color.alphaBlend(
          estado.acento.withValues(alpha: estado.pedeAcao ? .12 : .05),
          kGlassBg,
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Builder(
          builder: (context) => DefaultTextStyle.merge(
            textAlign: TextAlign.start,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassIconTile(
                  icon: _iconeTipo(questao.tipo),
                  ink: MistakeMapDesign.azureInk,
                  accent: MistakeMapDesign.azure,
                  size: 40,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          questao.materia.toUpperCase(),
                          questao.tipo.rotulo.toUpperCase(),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tipo.caption?.copyWith(
                          color: MistakeMapDesign.azureInk,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        questao.enunciado,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.tipo.bodyStrong?.copyWith(
                          color: MistakeMapDesign.abyss,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _Pilula(
                            texto: estado.label,
                            cor: estado.tinta,
                            icone: estado.icone,
                          ),
                          _Pilula(texto: questao.tema, cor: contentBlue),
                          if (dificuldade != null)
                            _Pilula(texto: dificuldade, cor: contentBlue),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Responder questão ────────────────────────────────────────────────────────

/// Responde uma questão e mostra a correção do servidor. "Próximo" segue
/// pela mesma lista filtrada de onde o aluno veio.
class TelaResponderQuestao extends StatefulWidget {
  const TelaResponderQuestao({
    super.key,
    required this.questoes,
    required this.inicial,
    required this.repositorio,
    this.onVerMapa,
  });

  final List<Questao> questoes;
  final int inicial;
  final RepositorioQuestoes repositorio;

  /// Primeira análise guiada: depois da correção, o botão principal leva
  /// ao Mapa de erros em vez de seguir para o próximo exercício.
  final VoidCallback? onVerMapa;

  @override
  State<TelaResponderQuestao> createState() => _TelaResponderQuestaoState();
}

class _TelaResponderQuestaoState extends State<TelaResponderQuestao> {
  late int _indice = widget.inicial;
  String? _escolha;
  final Set<String> _escolhas = {};
  final Map<String, bool> _vf = {};
  final _numero = TextEditingController();
  final Map<String, TextEditingController> _lacunas = {};
  List<String> _ordem = [];
  final Map<String, String> _pares = {};
  final _texto = TextEditingController();
  bool _enviando = false;
  CorrecaoQuestao? _correcao;
  String? _erro;
  final _rolagem = ScrollController();

  Questao get _q => widget.questoes[_indice];
  bool get _travada => _correcao != null || _enviando;

  @override
  void initState() {
    super.initState();
    _preparar();
  }

  @override
  void dispose() {
    _numero.dispose();
    _texto.dispose();
    for (final c in _lacunas.values) {
      c.dispose();
    }
    _rolagem.dispose();
    super.dispose();
  }

  void _preparar() {
    _escolha = null;
    _escolhas.clear();
    _vf.clear();
    _numero.clear();
    _texto.clear();
    for (final c in _lacunas.values) {
      c.dispose();
    }
    _lacunas
      ..clear()
      ..addAll({for (final b in _q.lacunas) b.id: TextEditingController()});
    _ordem = [for (final i in _q.itens) i.id];
    _pares.clear();
    _correcao = null;
    _erro = null;
  }

  /// O que falta preencher antes de enviar (nulo quando está completo).
  String? get _faltando => switch (_q.tipo) {
    TipoQuestao.multiplaEscolha =>
      _escolha == null ? 'Escolha uma alternativa.' : null,
    TipoQuestao.multiplaSelecao =>
      _escolhas.isEmpty ? 'Marque pelo menos uma alternativa.' : null,
    TipoQuestao.verdadeiroFalso =>
      _vf.length < _q.afirmacoes.length
          ? 'Marque V ou F em todas as afirmações.'
          : null,
    TipoQuestao.numerica =>
      _numero.text.trim().isEmpty ? 'Digite o valor.' : null,
    TipoQuestao.lacuna =>
      _lacunas.values.any((c) => c.text.trim().isEmpty)
          ? 'Preencha todas as lacunas.'
          : null,
    TipoQuestao.ordenacao => null,
    TipoQuestao.associacao =>
      _pares.length < _q.colunaA.length ? 'Associe todos os itens.' : null,
    TipoQuestao.dissertativa =>
      _texto.text.trim().length < 3 ? 'Escreva sua resposta.' : null,
  };

  Future<void> _enviar() async {
    final falta = _faltando;
    if (falta != null) {
      setState(() => _erro = falta);
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final correcao = await widget.repositorio.responder(
        _q.id,
        respostaPara(
          _q.tipo,
          escolha: _escolha,
          escolhas: _escolhas,
          verdadeiroFalso: _vf,
          numero: _numero.text,
          lacunas: {for (final e in _lacunas.entries) e.key: e.value.text},
          ordem: _ordem,
          pares: _pares,
          texto: _texto.text,
        ),
      );
      if (!mounted) return;
      setState(() => _correcao = correcao);
      notifyAnalysisChanged();
      // Leva o resultado para a vista, abaixo da resposta.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_rolagem.hasClients) {
          _rolagem.animateTo(
            _rolagem.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _erro = e is FalhaQuestao
            ? e.mensagem
            : 'Não foi possível corrigir agora. Tente de novo.',
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _irPara(int indice) {
    setState(() {
      _indice = indice;
      _preparar();
    });
    if (_rolagem.hasClients) _rolagem.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    final dificuldade = rotulosDificuldade[q.dificuldade];
    return _PaginaVidro(
      titulo: q.tipo.rotulo,
      voltar: true,
      corpo: SingleChildScrollView(
        controller: _rolagem,
        padding: _paddingCorpo(context),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Exercício ${_indice + 1} de ${widget.questoes.length}',
                  style: context.tipo.caption?.copyWith(color: contentBlue),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _Pilula(
                      texto: q.materia,
                      cor: MistakeMapDesign.azureInk,
                      icone: _iconeTipo(q.tipo),
                    ),
                    _Pilula(texto: q.tema, cor: contentBlue),
                    if (dificuldade != null)
                      _Pilula(texto: dificuldade, cor: contentBlue),
                  ],
                ),
                const SizedBox(height: 16),
                _CartaoFluent(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    q.enunciado,
                    style: context.tipo.body?.copyWith(
                      color: MistakeMapDesign.abyss,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _resposta(context),
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  InfoBar(
                    title: Text(_erro!),
                    severity: InfoBarSeverity.warning,
                  ),
                ],
                const SizedBox(height: 20),
                if (_correcao == null)
                  MistakeMapFilledButton(
                    key: const Key('questao-enviar'),
                    style: _estiloBotao(
                      fundo: kAcento,
                      texto: MistakeMapDesign.abyss,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                    ),
                    onPressed: _enviando ? null : _enviar,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_enviando)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: ProgressRing(strokeWidth: 2.5),
                          )
                        else
                          const Icon(WindowsIcons.send, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _enviando
                              ? (q.tipo == TipoQuestao.dissertativa
                                    ? 'A IA está corrigindo…'
                                    : 'Corrigindo…')
                              : 'Enviar resposta',
                        ),
                      ],
                    ),
                  )
                else ...[
                  _ResultadoQuestao(correcao: _correcao!),
                  const SizedBox(height: 16),
                  if (widget.onVerMapa != null) ...[
                    MistakeMapFilledButton(
                      key: const Key('questao-ver-mapa'),
                      style: _estiloBotao(
                        fundo: kAcento,
                        texto: MistakeMapDesign.abyss,
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 20,
                        ),
                      ),
                      onPressed: widget.onVerMapa,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(WindowsIcons.relationship, size: 18),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Ver meu mapa de erros',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: MistakeMapButton(
                          key: const Key('questao-de-novo'),
                          style: _estiloBotao(fonte: 14),
                          onPressed: () => setState(_preparar),
                          child: const Text('Tentar de novo'),
                        ),
                      ),
                      if (_indice + 1 < widget.questoes.length) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: MistakeMapFilledButton(
                            key: const Key('questao-proxima'),
                            style: _estiloBotao(
                              fonte: 14,
                              fundo: kAcento,
                              texto: MistakeMapDesign.abyss,
                            ),
                            onPressed: () => _irPara(_indice + 1),
                            child: const Text('Próximo exercício'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Acerto do item depois da correção (nulo antes de enviar).
  bool? _acertou(String id) => _correcao?.itens[id];

  Widget _resposta(BuildContext context) {
    final q = _q;
    switch (q.tipo) {
      case TipoQuestao.multiplaEscolha:
      case TipoQuestao.multiplaSelecao:
        final multipla = q.tipo == TipoQuestao.multiplaSelecao;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (multipla)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Marque todas as corretas.',
                  style: context.tipo.caption?.copyWith(color: contentBlue),
                ),
              ),
            for (final o in q.alternativas)
              _OpcaoResposta(
                key: Key('opcao-${o.id}'),
                letra: o.id,
                texto: o.texto,
                multipla: multipla,
                selecionada: multipla
                    ? _escolhas.contains(o.id)
                    : _escolha == o.id,
                acertou: multipla
                    ? _acertou(o.id)
                    : (_escolha == o.id ? _acertou(o.id) : null),
                onPressed: _travada
                    ? null
                    : () => setState(() {
                        _erro = null;
                        if (!multipla) {
                          _escolha = o.id;
                        } else if (!_escolhas.remove(o.id)) {
                          _escolhas.add(o.id);
                        }
                      }),
              ),
          ],
        );
      case TipoQuestao.verdadeiroFalso:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in q.afirmacoes)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CaixaItem(
                  acertou: _acertou(s.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${s.id}) ${s.texto}',
                        style: context.tipo.body?.copyWith(
                          color: MistakeMapDesign.abyss,
                        ),
                      ),
                      const SizedBox(height: 8),
                      IgnorePointer(
                        ignoring: _travada,
                        child: GlassSegmented<bool?>(
                          accent: MistakeMapDesign.azure,
                          ink: MistakeMapDesign.azureInk,
                          segments: [
                            (
                              value: true,
                              label: const Text('Verdadeiro'),
                              icon: null,
                              key: Key('vf-${s.id}-v'),
                            ),
                            (
                              value: false,
                              label: const Text('Falso'),
                              icon: null,
                              key: Key('vf-${s.id}-f'),
                            ),
                          ],
                          // Sem resposta: nenhum segmento aceso.
                          selected: _vf[s.id],
                          onSelected: (v) => setState(() {
                            _erro = null;
                            if (v != null) _vf[s.id] = v;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      case TipoQuestao.numerica:
        return _CaixaItem(
          acertou: _acertou('valor'),
          child: InfoLabel(
            label: 'Sua resposta',
            labelStyle: context.tipo.bodyStrong?.copyWith(color: contentBlue),
            child: TextBox(
              key: const Key('questao-numero'),
              controller: _numero,
              readOnly: _travada,
              placeholder: 'Ex.: 12,5',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              onChanged: (_) {
                if (_erro != null) setState(() => _erro = null);
              },
              suffix: q.unidade.isEmpty
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        q.unidade,
                        style: context.tipo.bodyStrong?.copyWith(
                          color: contentBlue,
                        ),
                      ),
                    ),
            ),
          ),
        );
      case TipoQuestao.lacuna:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final b in q.lacunas)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CaixaItem(
                  acertou: _acertou(b.id),
                  child: InfoLabel(
                    label: '(${b.id})',
                    labelStyle: context.tipo.bodyStrong?.copyWith(
                      color: contentBlue,
                    ),
                    child: TextBox(
                      key: Key('lacuna-${b.id}'),
                      controller: _lacunas[b.id],
                      readOnly: _travada,
                      placeholder: 'Complete a lacuna ${b.id}',
                      onChanged: (_) {
                        if (_erro != null) setState(() => _erro = null);
                      },
                    ),
                  ),
                ),
              ),
          ],
        );
      case TipoQuestao.ordenacao:
        final textos = {for (final i in q.itens) i.id: i.texto};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Use as setas para pôr os itens na ordem certa.',
                style: context.tipo.caption?.copyWith(color: contentBlue),
              ),
            ),
            for (var i = 0; i < _ordem.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CaixaItem(
                  acertou: _acertou(_ordem[i]),
                  child: Row(
                    children: [
                      Text(
                        '${i + 1}.',
                        style: context.tipo.bodyStrong?.copyWith(
                          color: MistakeMapDesign.azureInk,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          textos[_ordem[i]] ?? '',
                          style: context.tipo.body?.copyWith(
                            color: MistakeMapDesign.abyss,
                          ),
                        ),
                      ),
                      _BotaoBarra(
                        key: Key('ordem-sobe-$i'),
                        icone: WindowsIcons.chevron_up,
                        dica: 'Subir',
                        cor: contentBlue,
                        onPressed: _travada || i == 0
                            ? null
                            : () => setState(() {
                                final item = _ordem.removeAt(i);
                                _ordem.insert(i - 1, item);
                              }),
                      ),
                      _BotaoBarra(
                        key: Key('ordem-desce-$i'),
                        icone: WindowsIcons.chevron_down,
                        dica: 'Descer',
                        cor: contentBlue,
                        onPressed: _travada || i == _ordem.length - 1
                            ? null
                            : () => setState(() {
                                final item = _ordem.removeAt(i);
                                _ordem.insert(i + 1, item);
                              }),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      case TipoQuestao.associacao:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final l in q.colunaA)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CaixaItem(
                  acertou: _acertou(l.id),
                  child: InfoLabel(
                    label: l.texto,
                    labelStyle: context.tipo.bodyStrong?.copyWith(
                      color: MistakeMapDesign.abyss,
                    ),
                    child: ComboBox<String>(
                      key: Key('par-${l.id}'),
                      isExpanded: true,
                      value: _pares[l.id],
                      placeholder: const Text('Escolha o par'),
                      items: [
                        for (final r in q.colunaB)
                          ComboBoxItem(
                            value: r.id,
                            child: Text(
                              r.texto,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _travada
                          ? null
                          : (v) => setState(() {
                              _erro = null;
                              if (v != null) _pares[l.id] = v;
                            }),
                    ),
                  ),
                ),
              ),
          ],
        );
      case TipoQuestao.dissertativa:
        return InfoLabel(
          label: 'Sua resposta',
          labelStyle: context.tipo.bodyStrong?.copyWith(color: contentBlue),
          child: TextBox(
            key: const Key('questao-texto'),
            controller: _texto,
            readOnly: _travada,
            minLines: 5,
            maxLines: 12,
            maxLength: 8000,
            placeholder: 'Explique com suas palavras. A IA corrige.',
            onChanged: (_) {
              if (_erro != null) setState(() => _erro = null);
            },
          ),
        );
    }
  }
}

/// Moldura de um item da resposta: ganha cor e ícone depois da correção.
class _CaixaItem extends StatelessWidget {
  const _CaixaItem({required this.child, this.acertou});

  final Widget child;
  final bool? acertou;

  @override
  Widget build(BuildContext context) {
    final cor = switch (acertou) {
      true => MistakeMapDesign.mintInk,
      false => MistakeMapDesign.coralInk,
      null => MistakeMapDesign.fieldBorder,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: acertou == null
            ? MistakeMapDesign.white
            : cor.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(kRadiusSm),
        border: Border.all(
          color: cor.withValues(alpha: acertou == null ? 1 : .6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: child),
          if (acertou != null) ...[
            const SizedBox(width: 8),
            Semantics(
              label: acertou! ? 'Certo' : 'Errado',
              child: Icon(
                acertou! ? WindowsIcons.completed : WindowsIcons.error_badge,
                size: 18,
                color: cor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Alternativa clicável (escolha única ou várias).
class _OpcaoResposta extends StatelessWidget {
  const _OpcaoResposta({
    super.key,
    required this.letra,
    required this.texto,
    required this.multipla,
    required this.selecionada,
    required this.onPressed,
    this.acertou,
  });

  final String letra;
  final String texto;
  final bool multipla;
  final bool selecionada;
  final bool? acertou;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cor = switch (acertou) {
      true => MistakeMapDesign.mintInk,
      false => MistakeMapDesign.coralInk,
      null => selecionada ? MistakeMapDesign.azureInk : MistakeMapDesign.steel,
    };
    final fundo = acertou != null
        ? cor.withValues(alpha: .08)
        : selecionada
        ? MistakeMapDesign.azure.withValues(alpha: .14)
        : MistakeMapDesign.white;
    final icone = multipla
        ? (selecionada
              ? WindowsIcons.checkbox_composite
              : WindowsIcons.checkbox)
        : (selecionada
              ? WindowsIcons.radio_btn_on
              : WindowsIcons.radio_btn_off);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selecionada,
        inMutuallyExclusiveGroup: !multipla,
        checked: multipla ? selecionada : null,
        child: MistakeMapButton(
          onPressed: onPressed,
          style: MistakeMapControls.button(
            radius: kRadiusSm,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            background: fundo,
          ),
          child: Row(
            children: [
              Icon(icone, size: 18, color: cor),
              const SizedBox(width: 10),
              Text(
                '$letra)',
                style: context.tipo.bodyStrong?.copyWith(color: cor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  texto,
                  textAlign: TextAlign.start,
                  style: context.tipo.body?.copyWith(
                    color: MistakeMapDesign.abyss,
                  ),
                ),
              ),
              if (acertou != null)
                Icon(
                  acertou! ? WindowsIcons.completed : WindowsIcons.error_badge,
                  size: 18,
                  color: cor,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Correção do servidor: acerto, tipo de erro, resposta e explicação.
class _ResultadoQuestao extends StatelessWidget {
  const _ResultadoQuestao({required this.correcao});

  final CorrecaoQuestao correcao;

  @override
  Widget build(BuildContext context) {
    final c = correcao;
    if (!c.corrigida) {
      return InfoBar(
        title: const Text('Resposta salva'),
        content: Text(
          c.mensagem.isEmpty
              ? 'A correção da IA ainda está em andamento. Volte daqui a pouco.'
              : c.mensagem,
        ),
        severity: InfoBarSeverity.info,
      );
    }
    final certa = c.correta!;
    final parcial = !certa && (c.nota ?? 0) > 0;
    final tinta = certa
        ? MistakeMapDesign.mintInk
        : parcial
        ? MistakeMapDesign.amberInk
        : MistakeMapDesign.coralInk;
    final titulo = certa
        ? 'Resposta certa!'
        : parcial
        ? 'Quase: ${((c.nota ?? 0) * 100).round()}% certo'
        : 'Resposta errada';
    return _PainelVidro(
      acento: certa ? MistakeMapDesign.mint : MistakeMapDesign.coral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                certa ? WindowsIcons.completed : WindowsIcons.error_badge,
                color: tinta,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  key: const Key('questao-resultado'),
                  style: context.tipo.subtitle?.copyWith(
                    color: tinta,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          for (final d in c.diagnosticos) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Tipo de erro:',
                  style: context.tipo.bodyStrong?.copyWith(color: contentBlue),
                ),
                _Pilula(
                  texto: _rotuloCategoria(d.categoria),
                  cor: MistakeMapDesign.violetInk,
                ),
              ],
            ),
            if (d.explicacao.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                d.explicacao,
                style: context.tipo.body?.copyWith(
                  color: MistakeMapDesign.abyss,
                  height: 1.4,
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Text(
            'RESPOSTA CORRETA',
            style: context.tipo.caption?.copyWith(
              color: contentBlue,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            c.respostaCorreta,
            style: context.tipo.bodyStrong?.copyWith(color: titleBlue),
          ),
          if (c.explicacao.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              c.explicacao,
              style: context.tipo.body?.copyWith(
                color: contentBlue,
                height: 1.4,
              ),
            ),
          ],
          if (!certa) ...[
            const SizedBox(height: 12),
            Text(
              'Este erro foi registrado no seu Mapa de erros.',
              style: context.tipo.caption?.copyWith(
                color: MistakeMapDesign.violetInk,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _rotuloCategoria(String categoria) => switch (categoria) {
  'calculo' => 'Cálculo',
  'conceito' => 'Conceito',
  'sinal' => 'Sinal',
  'interpretacao' => 'Interpretação',
  'procedimento' => 'Procedimento',
  'unidade' => 'Unidade',
  _ => 'Outro',
};

// ─── fim: Banco de exercícios ────────────────────────────────────────────────

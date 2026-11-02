part of 'main.dart';

// ─── Caderno de erros (SQLite local + Supabase) ───────────────────────────────
// CRUD sobre o banco do aparelho (lib/local, BANCO_LOCAL.md), que funciona sem
// internet e sincroniza com a tabela error_notes (lib/sync/caderno_sync.dart).
// A preferência "Ocultar revisados" fica no shared_preferences.

String _dataCurta(DateTime dt) =>
    '${dt.day.toString().padLeft(2, '0')}/'
    '${dt.month.toString().padLeft(2, '0')}/'
    '${dt.year}';

class TelaCadernoErros extends StatefulWidget {
  final AppUser user;
  final RegistroErroDao? dao;
  final PreferenciasCaderno preferencias;

  const TelaCadernoErros({
    super.key,
    required this.user,
    this.dao,
    this.preferencias = const PreferenciasCaderno(),
    this.aba = false,
  });

  /// Aberto como aba da navegação: sem botão Voltar.
  final bool aba;

  @override
  State<TelaCadernoErros> createState() => _TelaCadernoErrosState();
}

class _TelaCadernoErrosState extends State<TelaCadernoErros> {
  late final RegistroErroDao _dao = widget.dao ?? RegistroErroDao();
  List<RegistroErro> _registros = [];
  bool _ocultarRevisados = false;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      _ocultarRevisados = await widget.preferencias.ocultarRevisados();
    } catch (_) {
      // Sem preferência salva, a lista mostra tudo.
    }
    await _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) setState(() => _carregando = true);
    try {
      final lista = await _dao.listar(
        widget.user.id,
        ocultarRevisados: _ocultarRevisados,
      );
      if (mounted) {
        setState(() {
          _registros = lista;
          _carregando = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _avisar(context, 'Erro ao abrir o banco local: $e', erro: true);
    }
  }

  /// Leva a alteração para os outros aparelhos sem esperar a próxima rodada.
  void _sincronizar() =>
      unawaited(Sincronizador.instancia.sincronizarAlteracao());

  Future<void> _alternarFiltro() async {
    setState(() => _ocultarRevisados = !_ocultarRevisados);
    try {
      await widget.preferencias.salvarOcultarRevisados(_ocultarRevisados);
    } catch (_) {
      // O filtro vale nesta sessão mesmo se a preferência não gravar.
    }
    await _carregar();
  }

  Future<void> _abrirFormulario([RegistroErro? registro]) async {
    final salvou = await Navigator.of(context).push<bool>(
      MistakeMapPageRoute(
        context: context,
        builder: (_) =>
            TelaRegistroErro(user: widget.user, dao: _dao, registro: registro),
      ),
    );
    if (salvou == true) {
      _sincronizar();
      await _carregar();
    }
  }

  Future<void> _marcarRevisado(RegistroErro r) async {
    try {
      await _dao.marcarRevisado(widget.user.id, r.id!, !r.revisado);
      _sincronizar();
      if (!mounted) return;
      _avisar(
        context,
        r.revisado ? 'Registro marcado como pendente.' : 'Registro revisado.',
      );
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      _avisar(context, 'Erro ao atualizar: $e', erro: true);
    }
  }

  Future<void> _confirmarExclusao(RegistroErro r) async {
    final ok = await _confirmar(
      context,
      titulo: 'Excluir registro',
      mensagem:
          'Excluir "${r.titulo}" do caderno?\n'
          'Esta ação não pode ser desfeita.',
      confirmar: 'Excluir',
      destrutivo: true,
    );
    if (!ok || !mounted) return;
    try {
      await _dao.excluir(widget.user.id, r.id!);
      _sincronizar();
      if (!mounted) return;
      _avisar(context, 'Registro excluído.');
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      _avisar(context, 'Erro ao excluir: $e', erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PaginaVidro(
      titulo: 'Caderno de erros',
      voltar: !widget.aba,
      acoes: [
        _BotaoBarra(
          icone: WindowsIcons.filter,
          dica: _ocultarRevisados ? 'Mostrar revisados' : 'Ocultar revisados',
          cor: _ocultarRevisados ? contentBlue : titleBlue,
          onPressed: _alternarFiltro,
        ),
        _BotaoBarra(
          icone: WindowsIcons.add,
          dica: 'Novo registro',
          onPressed: () => _abrirFormulario(),
        ),
      ],
      corpo: _corpo(context),
    );
  }

  Widget _corpo(BuildContext context) {
    if (_carregando && _registros.isEmpty) {
      return Padding(
        padding: _paddingCorpo(context),
        child: const Center(child: ProgressRing()),
      );
    }
    final intro = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        _ocultarRevisados
            ? 'Mostrando só os erros pendentes. Sincronizados com sua conta.'
            : 'Seus erros anotados ficam neste aparelho, mesmo sem internet, '
                  'e sincronizam com sua conta.',
        textAlign: TextAlign.center,
        style: context.tipo.body?.copyWith(color: contentBlue),
      ),
    );
    if (_registros.isEmpty) {
      return _ListaAtualizavel(
        onRefresh: _carregar,
        children: [
          intro,
          _CadernoVazio(onNovo: () => _abrirFormulario()),
        ],
      );
    }
    return _ListaAtualizavel(
      onRefresh: _carregar,
      children: [
        intro,
        for (final r in _registros)
          _RegistroErroCard(
            registro: r,
            onTap: () => _abrirFormulario(r),
            onRevisado: () => _marcarRevisado(r),
            onExcluir: () => _confirmarExclusao(r),
          ),
      ],
    );
  }
}

class _CadernoVazio extends StatelessWidget {
  const _CadernoVazio({required this.onNovo});

  final VoidCallback onNovo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Column(
        children: [
          Icon(
            WindowsIcons.quick_note,
            size: 72,
            color: contentBlue.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 24),
          Text(
            'Seu caderno ainda está vazio',
            textAlign: TextAlign.center,
            style: context.tipo.subtitle?.copyWith(
              fontWeight: FontWeight.bold,
              color: titleBlue,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Anote um erro para revisar depois.',
            textAlign: TextAlign.center,
            style: context.tipo.body?.copyWith(color: contentBlue),
          ),
          const SizedBox(height: 24),
          MistakeMapFilledButton(
            style: _estiloBotao(fundo: kAcento, texto: MistakeMapDesign.abyss),
            onPressed: onNovo,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(WindowsIcons.add, size: 18),
                SizedBox(width: 8),
                Text('Novo registro'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistroErroCard extends StatelessWidget {
  final RegistroErro registro;
  final VoidCallback onTap;
  final VoidCallback onRevisado;
  final VoidCallback onExcluir;

  const _RegistroErroCard({
    required this.registro,
    required this.onTap,
    required this.onRevisado,
    required this.onExcluir,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _CartaoFluent(
        onPressed: onTap,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Builder(
          builder: (context) => DefaultTextStyle.merge(
            textAlign: TextAlign.start,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              registro.titulo,
                              style: context.tipo.bodyStrong?.copyWith(
                                color: DefaultTextStyle.of(context).style.color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _Pilula(
                            texto: registro.revisado ? 'Revisado' : 'Pendente',
                            cor: registro.revisado
                                ? Cores.verde600
                                : Cores.laranja700,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        registro.descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.tipo.body?.copyWith(
                          color: DefaultTextStyle.of(context).style.color,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _Pilula(texto: registro.disciplina, cor: contentBlue),
                          _Pilula(
                            texto: registro.tipo.rotulo,
                            cor: _corDoTipo(registro.tipo),
                          ),
                          Text(
                            _dataCurta(registro.atualizadoEm),
                            style: context.tipo.caption?.copyWith(
                              color: DefaultTextStyle.of(context).style.color,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _menu(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menu() {
    return DropDownButton(
      placement: FlyoutPlacementMode.bottomRight,
      menuShape: MistakeMapControls.menuShape,
      menuColor: MistakeMapDesign.surface,
      buttonBuilder: (context, abrir) => _BotaoBarra(
        icone: WindowsIcons.more,
        dica: 'Opções',
        cor: contentBlue,
        onPressed: abrir,
      ),
      items: [
        _itemMenu(icone: WindowsIcons.edit, texto: 'Editar', onPressed: onTap),
        _itemMenu(
          icone: registro.revisado
              ? WindowsIcons.undo
              : WindowsIcons.check_mark,
          texto: registro.revisado
              ? 'Marcar como pendente'
              : 'Marcar como revisado',
          onPressed: onRevisado,
        ),
        _itemMenu(
          icone: WindowsIcons.delete,
          texto: 'Excluir',
          cor: Cores.vermelho700,
          onPressed: onExcluir,
        ),
      ],
    );
  }
}

// ─── Formulário de registro (criar e editar) ─────────────────────────────────
class TelaRegistroErro extends StatefulWidget {
  final AppUser user;
  final RegistroErroDao dao;

  /// Nulo para criar um registro novo.
  final RegistroErro? registro;

  const TelaRegistroErro({
    super.key,
    required this.user,
    required this.dao,
    this.registro,
  });

  @override
  State<TelaRegistroErro> createState() => _TelaRegistroErroState();
}

class _TelaRegistroErroState extends State<TelaRegistroErro> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _disciplinaCtrl;
  late final TextEditingController _tituloCtrl;
  late final TextEditingController _descricaoCtrl;
  late TipoErro _tipo;
  late bool _revisado;
  bool _salvando = false;

  bool get _editando => widget.registro != null;

  @override
  void initState() {
    super.initState();
    final r = widget.registro;
    _disciplinaCtrl = TextEditingController(text: r?.disciplina);
    _tituloCtrl = TextEditingController(text: r?.titulo);
    _descricaoCtrl = TextEditingController(text: r?.descricao);
    _tipo = r?.tipo ?? TipoErro.conceitual;
    _revisado = r?.revisado ?? false;
  }

  @override
  void dispose() {
    _disciplinaCtrl.dispose();
    _tituloCtrl.dispose();
    _descricaoCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);
    final agora = DateTime.now();
    try {
      final atual = widget.registro;
      if (atual == null) {
        await widget.dao.inserir(
          RegistroErro(
            usuarioId: widget.user.id,
            disciplina: _disciplinaCtrl.text.trim(),
            titulo: _tituloCtrl.text.trim(),
            descricao: _descricaoCtrl.text.trim(),
            tipo: _tipo,
            revisado: _revisado,
            criadoEm: agora,
            atualizadoEm: agora,
          ),
        );
      } else {
        await widget.dao.atualizar(
          atual.copyWith(
            disciplina: _disciplinaCtrl.text.trim(),
            titulo: _tituloCtrl.text.trim(),
            descricao: _descricaoCtrl.text.trim(),
            tipo: _tipo,
            revisado: _revisado,
            atualizadoEm: agora,
          ),
        );
      }
      if (!mounted) return;
      _avisar(context, _editando ? 'Registro atualizado!' : 'Registro salvo!');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _avisar(context, 'Erro ao salvar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  String? _obrigatorio(String? v, String mensagem) =>
      v == null || v.trim().isEmpty ? mensagem : null;

  @override
  Widget build(BuildContext context) {
    return _PaginaVidro(
      titulo: _editando ? 'Editar registro' : 'Novo registro',
      voltar: true,
      corpo: SingleChildScrollView(
        padding: _paddingCorpo(context),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _editando
                        ? 'Atualize as informações do registro.'
                        : 'Anote o erro para revisar depois.',
                    textAlign: TextAlign.center,
                    style: context.tipo.body?.copyWith(color: contentBlue),
                  ),
                  const SizedBox(height: 24),
                  _CartaoFluent(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AdicionarCampoTexto(
                          rotulo: 'Disciplina',
                          dica: 'Ex.: Matemática',
                          controller: _disciplinaCtrl,
                          validator: (v) =>
                              _obrigatorio(v, 'Informe a disciplina'),
                        ),
                        const SizedBox(height: 16),
                        _AdicionarCampoTexto(
                          rotulo: 'Título',
                          dica: 'Ex.: Sinal na fórmula de Bhaskara',
                          controller: _tituloCtrl,
                          validator: (v) => _obrigatorio(v, 'Informe o título'),
                        ),
                        const SizedBox(height: 16),
                        _AdicionarCampoTexto(
                          rotulo: 'O que você errou?',
                          dica: 'Descreva o erro e como corrigir',
                          controller: _descricaoCtrl,
                          minLines: 4,
                          maxLines: 8,
                          validator: (v) => _obrigatorio(v, 'Descreva o erro'),
                        ),
                        const SizedBox(height: 16),
                        InfoLabel(
                          label: 'Tipo de erro',
                          labelStyle: context.tipo.bodyStrong?.copyWith(
                            color: contentBlue,
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final t in TipoErro.values)
                                _opcao(
                                  texto: t.rotulo,
                                  selecionada: t == _tipo,
                                  onPressed: () => setState(() => _tipo = t),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        InfoLabel(
                          label: 'Situação',
                          labelStyle: context.tipo.bodyStrong?.copyWith(
                            color: contentBlue,
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _opcao(
                                texto: 'Pendente',
                                selecionada: !_revisado,
                                onPressed: () =>
                                    setState(() => _revisado = false),
                              ),
                              _opcao(
                                texto: 'Revisado',
                                selecionada: _revisado,
                                onPressed: () =>
                                    setState(() => _revisado = true),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  MistakeMapFilledButton(
                    style: _estiloBotao(
                      fundo: kAcento,
                      texto: MistakeMapDesign.abyss,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                    ),
                    onPressed: _salvando ? null : _salvar,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_salvando)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: ProgressRing(
                              strokeWidth: 2.5,
                              activeColor: Cores.branco,
                            ),
                          )
                        else
                          const Icon(WindowsIcons.check_mark, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _salvando
                              ? 'Salvando…'
                              : _editando
                              ? 'Salvar alterações'
                              : 'Salvar registro',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Opção de escolha única: a selecionada usa o botão preenchido do app.
  Widget _opcao({
    required String texto,
    required bool selecionada,
    required VoidCallback onPressed,
  }) {
    final estilo = _estiloBotao(
      fonte: 14,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      fundo: selecionada ? kAcento : null,
      texto: selecionada ? MistakeMapDesign.abyss : contentBlue,
    );
    return Semantics(
      selected: selecionada,
      button: true,
      child: selecionada
          ? MistakeMapFilledButton(
              style: estilo,
              onPressed: onPressed,
              child: Text(texto),
            )
          : MistakeMapButton(
              style: estilo,
              onPressed: onPressed,
              child: Text(texto),
            ),
    );
  }
}

// ─── fim: Caderno de erros ───────────────────────────────────────────────────

// Cada tipo de erro mantém a cor que tem no Mapa, sempre ao lado do rótulo.
Color _corDoTipo(TipoErro tipo) => switch (tipo) {
  TipoErro.conceitual => MistakeMapDesign.violetInk,
  TipoErro.calculo => MistakeMapDesign.azureInk,
  TipoErro.interpretacao => MistakeMapDesign.aquaInk,
  TipoErro.atencao => MistakeMapDesign.amberInk,
};

import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/control_styles.dart';
import '../theme/design_tokens.dart';
import '../theme/glass_surface.dart';
import 'study_repository.dart';

export 'study_repository.dart';

const _stageLabels = {
  'fundamental': 'Ensino Fundamental',
  'medio': 'Ensino Médio',
  'superior': 'Ensino Superior',
  'autodidata': 'Estudo independente',
};

const _categoryLabels = {
  'calculo': 'Cálculo',
  'conceito': 'Conceito',
  'sinal': 'Sinal',
  'interpretacao': 'Interpretação',
  'procedimento': 'Procedimento',
  'unidade': 'Unidade',
  'outro': 'Outro',
};

/// Embeddable in Início; keeps the existing navigation and study flows.
class StudyTodayPanel extends StatefulWidget {
  const StudyTodayPanel({
    super.key,
    required this.userId,
    this.client,
    this.repository,
    this.onExplore,
    this.onAnalyze,
    this.onStudy,
  });

  final String userId;
  final SupabaseClient? client;
  final StudyRepository? repository;
  final VoidCallback? onExplore;
  final VoidCallback? onAnalyze;
  final VoidCallback? onStudy;

  @override
  State<StudyTodayPanel> createState() => StudyTodayPanelState();
}

class StudyTodayPanelState extends State<StudyTodayPanel>
    with WidgetsBindingObserver {
  late StudyRepository _repository;
  bool _ownsRepository = false;
  StudyDashboard? _dashboard;
  StudySession? _session;
  List<StudyPendingAnswer> _pending = [];
  String? _error;
  String? _notice;
  bool _loading = true;
  bool _busy = false;
  bool _refreshing = false;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    _attach();
    WidgetsBinding.instance.addObserver(this);
    _retry = Timer.periodic(const Duration(seconds: 20), (_) {
      final state = _repository.syncState.value;
      if (!_busy && (state.offline || state.pending > 0)) unawaited(refresh());
    });
    unawaited(refresh());
  }

  void _attach() {
    _ownsRepository = widget.repository == null;
    _repository =
        widget.repository ??
        SupabaseStudyRepository(widget.client ?? Supabase.instance.client);
    _repository.syncState.addListener(_syncChanged);
  }

  void _syncChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant StudyTodayPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userId != oldWidget.userId ||
        widget.repository != oldWidget.repository ||
        widget.client != oldWidget.client) {
      _repository.syncState.removeListener(_syncChanged);
      if (_ownsRepository) _repository.dispose();
      _attach();
      _dashboard = null;
      _session = null;
      _pending = [];
      _error = null;
      _notice = null;
      _loading = true;
      _refreshing = false;
      unawaited(refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  /// Called by the host when returning to Início, and on app resume/reconnect.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final repository = _repository;
    final userId = widget.userId;
    try {
      final dashboard = await repository.loadDashboard(userId);
      final pending = await repository.pendingAnswers(userId);
      final session = await repository.loadSession(userId);
      if (!mounted || repository != _repository || userId != widget.userId) {
        return;
      }
      setState(() {
        _dashboard = dashboard;
        _pending = pending;
        _session = session;
        _error = null;
      });
    } catch (error) {
      if (!mounted || repository != _repository || userId != widget.userId) {
        return;
      }
      setState(() => _error = _message(error));
    } finally {
      if (mounted && repository == _repository && userId == widget.userId) {
        _refreshing = false;
        setState(() => _loading = false);
      }
    }
  }

  String _message(Object error) => error is StudyFailure
      ? error.message
      : 'Não foi possível concluir. Tente novamente.';

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editProfile() async {
    if (_busy) return;
    StudyProfileData? data;
    await _run(() async {
      data = await _repository.loadProfile(widget.userId);
    });
    if (!mounted || data == null) return;
    final profile = await showDialog<StudyProfile>(
      context: context,
      builder: (_) => _StudyProfileDialog(data: data!),
    );
    if (profile == null) return;
    await _run(() async {
      await _repository.saveProfile(widget.userId, profile);
      if (mounted) {
        setState(
          () => _notice =
              'Seu objetivo foi salvo. O plano usa o tempo que você escolheu.',
        );
      }
      await refresh();
    });
  }

  Future<void> _review() async {
    if (_busy) return;
    StudySession? session;
    await _run(() async {
      session = _session?.status == 'active'
          ? _session!
          : await _repository.startSession(
              widget.userId,
              minutes: _dashboard?.profile?.dailyMinutes ?? 15,
            );
    });
    if (!mounted) return;
    if (session == null) {
      setState(
        () => _notice = 'Ainda não há revisões confirmadas. Confira uma sugestão da IA ou analise um exercício para começar.',
      );
      return;
    }
    await Navigator.of(context).push<void>(
      FluentPageRoute(
        builder: (_) => StudyReviewPage(
          userId: widget.userId,
          repository: _repository,
          initialSession: session!,
        ),
      ),
    );
    await refresh();
  }

  Future<void> _diagnostics() async {
    if (!mounted || _busy) return;
    await Navigator.of(context).push<void>(
      FluentPageRoute(
        builder: (_) => StudyDiagnosticsPage(
          userId: widget.userId,
          repository: _repository,
        ),
      ),
    );
    await refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retry?.cancel();
    _repository.syncState.removeListener(_syncChanged);
    if (_ownsRepository) _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    final sync = _repository.syncState.value;
    final profile = dashboard?.profile;
    return Semantics(
      container: true,
      label: 'Seu estudo de hoje',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StudyCard(
            accent: MistakeMapDesign.aqua,
            children: [
              const _StudyTitle('Seu estudo de hoje', large: true),
              const SizedBox(height: 8),
              const Text('Um próximo passo que cabe na sua rotina.'),
              if (_loading) ...[
                const SizedBox(height: 24),
                // Centralizado e com tamanho fixo: na coluna esticada o anel
                // virava uma elipse da largura do cartão.
                Semantics(
                  label: 'Carregando seu estudo',
                  child: const Center(
                    child: SizedBox.square(
                      dimension: 32,
                      child: ProgressRing(),
                    ),
                  ),
                ),
              ] else if (dashboard != null) ...[
                const SizedBox(height: 24),
                if (profile == null) ...[
                  const Text(
                    'Como podemos ajudar você a estudar?',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Escolha seu objetivo, etapa e tempo disponível para preparar sua rotina.',
                  ),
                  const SizedBox(height: 16),
                  _StudyButton(
                    label: 'Definir meu objetivo',
                    onPressed: _busy ? null : _editProfile,
                    primary: true,
                  ),
                ] else ...[
                  Text(
                    profile.goal.isEmpty
                        ? _stageLabels[profile.stage] ?? 'Seu objetivo'
                        : profile.goal,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${profile.dailyMinutes} minutos por sessão · ${_stageLabels[profile.stage] ?? 'Estudo'}',
                  ),
                  const SizedBox(height: 24),
                  Text(
                    dashboard.dueCount > 0
                        ? '${_plural(dashboard.dueCount, 'revisão', 'revisões')} para hoje'
                        : 'Revisões em dia',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: MistakeMapDesign.abyss,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dashboard.dueCount > 0
                        ? 'Cerca de ${dashboard.estimatedMinutes} min, com pausas quando precisar.'
                        : 'Você pode praticar um novo conceito ou explorar conteúdos.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (dashboard.dueCount > 0 ||
                          _session?.status == 'active')
                        _StudyButton(
                          label: _session?.status == 'active'
                              ? 'Continuar revisão'
                              : 'Começar revisão',
                          onPressed: _busy ? null : _review,
                          primary: true,
                        ),
                      if (widget.onStudy != null)
                        _StudyButton(
                          label: 'Praticar um conceito',
                          onPressed: widget.onStudy,
                        ),
                      _StudyButton(
                        label: 'Ajustar objetivo',
                        onPressed: _busy ? null : _editProfile,
                      ),
                    ],
                  ),
                ],
              ],
              if (_busy) ...[const SizedBox(height: 16), const ProgressBar()],
              if (_error != null) ...[
                const SizedBox(height: 16),
                _StudyNotice(_error!, error: true),
                const SizedBox(height: 8),
                _StudyButton(
                  label: 'Tentar novamente',
                  onPressed: _busy ? null : refresh,
                ),
              ],
              if (_notice != null) ...[
                const SizedBox(height: 16),
                _StudyNotice(_notice!),
              ],
              if (sync.offline || sync.pending > 0 || sync.rejected > 0) ...[
                const SizedBox(height: 16),
                _StudyNotice(
                  sync.offline
                      ? 'Sem conexão. Exibindo o estudo salvo neste aparelho.'
                      : 'Respostas salvas neste aparelho: ${sync.pending} aguardando envio, ${sync.rejected} precisam de atenção.',
                ),
                if (sync.pending > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_plural(sync.pending, 'autoavaliação aguarda', 'autoavaliações aguardam')} envio. A agenda será atualizada ao sincronizar.',
                  ),
                ],
                if (sync.updatedAt != null)
                  Text(
                    'Última atualização: ${_dateTime(context, sync.updatedAt!)}',
                  ),
                if (sync.message != null)
                  _StudyNotice(sync.message!, error: true),
              ],
              for (final pending in _pending.where(
                (item) => item.failure != null,
              )) ...[
                const SizedBox(height: 16),
                _StudyNotice(
                  'Uma resposta não foi aceita: ${pending.failure}',
                  error: true,
                ),
                _StudyButton(
                  label: 'Descartar resposta recusada',
                  onPressed: _busy ? null : () => _discard(pending),
                ),
              ],
            ],
          ),
          if (dashboard != null) ...[
            const SizedBox(height: 16),
            if (dashboard.pendingDiagnostics > 0) ...[
              _StudyCard(
                accent: MistakeMapDesign.amber,
                children: [
                  const _StudyTitle('Confira suas correções'),
                  const SizedBox(height: 8),
                  Text(
                    '${_plural(dashboard.pendingDiagnostics, 'sugestão aguarda', 'sugestões aguardam')} sua conferência. Você confirma, corrige ou rejeita.',
                  ),
                  const SizedBox(height: 16),
                  _StudyButton(
                    label: 'Conferir sugestões',
                    onPressed: _busy ? null : _diagnostics,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _StudyCard(
              accent: MistakeMapDesign.mint,
              children: [
                const _StudyTitle('Sua semana de revisão'),
                const SizedBox(height: 8),
                Text(
                  '${_plural(dashboard.progress.reviews, 'autoavaliação', 'autoavaliações')} nos últimos ${dashboard.progress.periodDays} dias.',
                ),
                const SizedBox(height: 8),
                if (dashboard.progress.recallRate != null &&
                    dashboard.progress.reviews > 0)
                  Text(
                    'Você relatou lembrar em ${(dashboard.progress.recallRate! * 100).round()}% dessas revisões.',
                  )
                else
                  const Text(
                    'Ainda não há amostra suficiente para mostrar sua lembrança relatada.',
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Esta medida usa a sua autoavaliação. Ela não representa nota, acerto em prova ou domínio comprovado.',
                ),
                const SizedBox(height: 8),
                Text(
                  dashboard.reviewedToday == 0
                      ? 'Nenhuma revisão registrada hoje.'
                      : 'Hoje: ${_plural(dashboard.reviewedToday, 'revisão registrada', 'revisões registradas')}.',
                ),
              ],
            ),
          ],
          if (widget.onExplore != null || widget.onAnalyze != null) ...[
            const SizedBox(height: 16),
            _StudyActions(
              children: [
                if (widget.onExplore != null)
                  _StudyActionButton(
                    key: const Key('study-explore'),
                    icon: WindowsIcons.education,
                    label: 'Explorar conteúdos',
                    accent: MistakeMapDesign.azure,
                    onPressed: widget.onExplore,
                  ),
                if (widget.onAnalyze != null)
                  _StudyActionButton(
                    key: const Key('study-analyze'),
                    icon: WindowsIcons.camera,
                    label: 'Enviar exercício',
                    accent: MistakeMapDesign.violet,
                    onPressed: widget.onAnalyze,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _discard(StudyPendingAnswer pending) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Descartar resposta recusada?'),
        content: const Text(
          'Só esta resposta local será removida. A revisão poderá ser retomada a partir do estado atual do servidor.',
        ),
        actions: [
          _StudyButton(
            label: 'Manter resposta',
            onPressed: () => Navigator.pop(context, false),
          ),
          _StudyButton(
            label: 'Descartar',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await _repository.discardAnswer(widget.userId, pending.eventId);
      await refresh();
    });
  }
}

/// "1 autoavaliação", "3 autoavaliações": evita o "(ões)" no texto.
String _plural(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';

String _dateTime(BuildContext context, DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class _StudyProfileDialog extends StatefulWidget {
  const _StudyProfileDialog({required this.data});
  final StudyProfileData data;
  @override
  State<_StudyProfileDialog> createState() => _StudyProfileDialogState();
}

class _StudyProfileDialogState extends State<_StudyProfileDialog> {
  late final TextEditingController _goal;
  late String _stage;
  late int _minutes;
  String? _error;
  @override
  void initState() {
    super.initState();
    final profile = widget.data.profile;
    _goal = TextEditingController(text: profile?.goal ?? '');
    _stage = profile?.stage ?? 'autodidata';
    _minutes = profile?.dailyMinutes ?? 15;
  }

  @override
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentDialog(
    title: const Text('Seu objetivo de estudo'),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Uma rotina que respeita seu momento. Você pode ajustar depois.',
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'O que você quer alcançar?',
            child: TextBox(
              key: const Key('study-goal'),
              controller: _goal,
              maxLength: 240,
              maxLines: 3,
              placeholder:
                  'Ex.: entender circuitos elétricos para a próxima prova',
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Sua etapa',
            child: ComboBox<String>(
              key: const Key('study-stage'),
              value: _stage,
              isExpanded: true,
              items: [
                for (final stage in _stageLabels.entries)
                  ComboBoxItem(value: stage.key, child: Text(stage.value)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _stage = value);
              },
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Minutos por sessão',
            child: NumberBox<int>(
              key: const Key('study-minutes'),
              value: _minutes,
              min: 5,
              max: 180,
              mode: SpinButtonPlacementMode.inline,
              onChanged: (value) {
                if (value != null) setState(() => _minutes = value);
              },
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'A revisão usa seus próprios conceitos e exercícios. Novos exercícios mantêm situações de tecnologia adequadas à sua etapa.',
          ),
          if (_error != null) _StudyNotice(_error!, error: true),
        ],
      ),
    ),
    actions: [
      _StudyButton(label: 'Agora não', onPressed: () => Navigator.pop(context)),
      _StudyButton(
        label: 'Salvar objetivo',
        primary: true,
        onPressed: () {
          if (_goal.text.trim().isEmpty) {
            setState(
              () => _error = 'Conte seu objetivo para personalizar seu estudo.',
            );
            return;
          }
          final old = widget.data.profile;
          Navigator.pop(
            context,
            StudyProfile(
              stage: _stage,
              dailyMinutes: _minutes,
              goal: _goal.text.trim(),
              timezone: old?.timezone ?? 'America/Sao_Paulo',
              subjectIds: old?.subjectIds ?? const [],
              examDate: old?.examDate,
              remindersEnabled: old?.remindersEnabled ?? false,
            ),
          );
        },
      ),
    ],
  );
}

class StudyReviewPage extends StatefulWidget {
  const StudyReviewPage({
    super.key,
    required this.userId,
    required this.repository,
    required this.initialSession,
  });
  final String userId;
  final StudyRepository repository;
  final StudySession initialSession;
  @override
  State<StudyReviewPage> createState() => _StudyReviewPageState();
}

class _StudyReviewPageState extends State<StudyReviewPage> {
  late StudySession _session;
  final _draft = TextEditingController();
  final _watch = Stopwatch();
  String? _itemId;
  String? _error;
  StudyAnswerResult? _feedback;
  bool _reference = false;
  String _referenceText = '';
  bool _busy = false;
  Timer? _saveTimer;
  Future<void> _draftWrite = Future.value();

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    unawaited(_prepareItem());
  }

  Future<void> _prepareItem() async {
    final item = _session.remaining.firstOrNull;
    _itemId = item?.id;
    _draft.clear();
    _reference = false;
    _referenceText = '';
    _watch
      ..reset()
      ..start();
    if (item == null) return;
    final saved = await widget.repository.loadDraft(widget.userId, item.id);
    if (!mounted || _itemId != item.id) return;
    setState(() => _draft.text = saved);
  }

  void _changed(String text) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _saveDraft);
  }

  void _saveDraft() {
    final itemId = _itemId;
    if (itemId == null) return;
    _draftWrite = widget.repository
        .saveDraft(widget.userId, itemId, _draft.text)
        .catchError((Object error) {
          if (mounted) {
            setState(
              () => _error = error is StudyFailure
                  ? error.message
                  : 'Não foi possível salvar seu rascunho neste aparelho.',
            );
          }
        });
  }

  Future<void> _answer(String rating) async {
    final item = _session.remaining.firstOrNull;
    if (_busy || item == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _saveTimer?.cancel();
    _saveDraft();
    await _draftWrite;
    try {
      final result = await widget.repository.answer(
        widget.userId,
        sessionId: _session.id,
        itemId: item.id,
        rating: rating,
        elapsedSeconds: _watch.elapsed.inSeconds,
      );
      if (!mounted) return;
      setState(() {
        _session = result.session;
        _feedback = result;
        _itemId = null;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StudyFailure
              ? error.message
              : 'Não foi possível registrar. Sua revisão continua aberta.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reveal() async {
    final itemId = _itemId;
    if (_busy || itemId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await widget.repository.revealReference(
        widget.userId,
        _session.id,
        itemId,
      );
      if (mounted) {
        setState(() {
          _referenceText = text;
          _reference = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StudyFailure
              ? error.message
              : 'Não foi possível conferir a referência.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveDraft();
    _watch.stop();
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = _session.remaining.firstOrNull;
    final feedback = _feedback;
    return NavigationView(
      content: ScaffoldPage.scrollable(
        header: PageHeader(
          title: const Text('Sua revisão'),
          leading: _StudyButton(
            label: 'Voltar',
            onPressed: () => Navigator.pop(context),
          ),
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _StudyCard(
                accent: MistakeMapDesign.violet,
                children: [
                  if (feedback != null) ...[
                    _StudyTitle(
                      feedback.queued
                          ? 'Resposta salva neste aparelho'
                          : 'Autoavaliação registrada',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      feedback.queued
                          ? 'Ela será enviada automaticamente quando a conexão voltar. A próxima data ainda depende do servidor.'
                          : 'A agenda foi atualizada a partir da sua autoavaliação.',
                    ),
                    if (feedback.reference?.isNotEmpty == true) ...[
                      const SizedBox(height: 16),
                      const _StudyTitle('Referência da tentativa anterior'),
                      const SizedBox(height: 8),
                      SelectableText(feedback.reference!),
                    ],
                    if (feedback.nextDueAt != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Próxima revisão: ${_dateTime(context, feedback.nextDueAt!)}',
                      ),
                    ],
                    const SizedBox(height: 24),
                    _StudyButton(
                      label: item == null
                          ? 'Ver conclusão'
                          : 'Próximo conceito',
                      primary: true,
                      onPressed: () async {
                        setState(() => _feedback = null);
                        await _prepareItem();
                      },
                    ),
                  ] else if (item == null) ...[
                    const _StudyTitle('Você concluiu esta rodada'),
                    const SizedBox(height: 16),
                    const Text(
                      'Sua lembrança foi registrada por autoavaliação. Praticar questões novas ajuda a verificar o que você aprendeu.',
                    ),
                    const SizedBox(height: 16),
                    ValueListenableBuilder<StudySyncState>(
                      valueListenable: widget.repository.syncState,
                      builder: (context, state, _) => Text(
                        state.pending > 0
                            ? '${_plural(state.pending, 'resposta ainda aguarda', 'respostas ainda aguardam')} envio. Mantenha o aplicativo aberto ao reconectar.'
                            : 'Respostas desta rodada enviadas ao servidor.',
                      ),
                    ),
                    const SizedBox(height: 24),
                    _StudyButton(
                      label: 'Voltar ao meu estudo',
                      primary: true,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ] else ...[
                    Text(
                      '${_session.items.length - _session.remaining.length + 1} de ${_session.items.length} · ${item.subjectName}',
                    ),
                    const SizedBox(height: 8),
                    _StudyTitle(item.conceptName, large: true),
                    if (item.reason.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(item.reason),
                    ],
                    const SizedBox(height: 24),
                    SelectableText(
                      item.prompt,
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 24),
                    InfoLabel(
                      label: 'Tente explicar ou resolver com suas palavras',
                      child: TextBox(
                        key: const Key('study-review-draft'),
                        controller: _draft,
                        onChanged: _changed,
                        minLines: 4,
                        maxLines: 8,
                        maxLength: 8000,
                        placeholder: 'Seu rascunho fica neste aparelho.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_reference)
                      _StudyButton(
                        label: 'Ver referência',
                        onPressed: _busy ? null : _reveal,
                      )
                    else ...[
                      const _StudyTitle('Referência da tentativa anterior'),
                      const SizedBox(height: 8),
                      SelectableText(
                        _referenceText.isEmpty
                            ? 'Não há uma referência salva para este conceito. Consulte seu material antes de se avaliar.'
                            : _referenceText,
                      ),
                      const SizedBox(height: 24),
                      const _StudyTitle('Como foi lembrar?'),
                      const SizedBox(height: 8),
                      const Text(
                        'Sua resposta é uma autoavaliação; não é uma correção automática do rascunho.',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final rating in const {
                            'again': 'Não lembrei',
                            'hard': 'Com dificuldade',
                            'good': 'Lembrei',
                            'easy': 'Foi fácil',
                          }.entries)
                            _StudyButton(
                              label: rating.value,
                              onPressed: _busy
                                  ? null
                                  : () => _answer(rating.key),
                            ),
                        ],
                      ),
                    ],
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const ProgressBar(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _StudyNotice(_error!, error: true),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StudyDiagnosticsPage extends StatefulWidget {
  const StudyDiagnosticsPage({
    super.key,
    required this.userId,
    required this.repository,
  });
  final String userId;
  final StudyRepository repository;
  @override
  State<StudyDiagnosticsPage> createState() => _StudyDiagnosticsPageState();
}

class _StudyDiagnosticsPageState extends State<StudyDiagnosticsPage> {
  List<StudyDiagnostic>? _items;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final items = await widget.repository.loadDiagnostics(widget.userId);
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StudyFailure
              ? error.message
              : 'Não foi possível carregar as sugestões.',
        );
      }
    }
  }

  Future<void> _decide(
    StudyDiagnostic diagnostic,
    String decision, {
    String? category,
    double? importance,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.decide(
        widget.userId,
        diagnostic.id,
        decision: decision,
        category: category,
        importance: importance,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StudyFailure
              ? error.message
              : 'Não foi possível salvar sua conferência.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _correct(StudyDiagnostic diagnostic) async {
    String category = _categoryLabels.containsKey(diagnostic.category)
        ? diagnostic.category
        : _categoryLabels.keys.first;
    double importance = const [.5, 1.0, 2.0].contains(diagnostic.importance)
        ? diagnostic.importance
        : 1;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ContentDialog(
          title: const Text('Corrigir classificação'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ajuste o tipo de erro e a importância para seu objetivo.',
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: 'Tipo de erro',
                  child: ComboBox<String>(
                    value: category,
                    isExpanded: true,
                    items: [
                      for (final entry in _categoryLabels.entries)
                        ComboBoxItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => category = value);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                InfoLabel(
                  label: 'Importância para você',
                  child: ComboBox<double>(
                    value: importance,
                    isExpanded: true,
                    items: const [
                      ComboBoxItem(value: .5, child: Text('Menor')),
                      ComboBoxItem(value: 1, child: Text('Normal')),
                      ComboBoxItem(value: 2, child: Text('Alta')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => importance = value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            _StudyButton(
              label: 'Cancelar',
              onPressed: () => Navigator.pop(context, false),
            ),
            _StudyButton(
              label: 'Salvar correção',
              primary: true,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      await _decide(
        diagnostic,
        'confirmed',
        category: category,
        importance: importance,
      );
    }
  }

  @override
  Widget build(BuildContext context) => NavigationView(
    content: ScaffoldPage.scrollable(
      header: PageHeader(
        title: const Text('Conferir sugestões'),
        leading: _StudyButton(
          label: 'Voltar',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      children: [
        const Text(
          'A IA pode errar. Uma sugestão só entra na sua revisão depois da sua confirmação.',
        ),
        const SizedBox(height: 24),
        if (_busy) const ProgressBar(),
        if (_error != null) ...[
          _StudyNotice(_error!, error: true),
          const SizedBox(height: 8),
          _StudyButton(
            label: 'Tentar novamente',
            onPressed: _busy ? null : _load,
          ),
        ],
        if (_items == null && _error == null)
          const Center(child: ProgressRing()),
        if (_items?.isEmpty == true)
          const _StudyCard(
            children: [
              _StudyTitle('Tudo conferido'),
              SizedBox(height: 8),
              Text(
                'Novas sugestões aparecerão aqui quando houver uma análise para você conferir.',
              ),
            ],
          ),
        for (final item in _items ?? <StudyDiagnostic>[]) ...[
          _StudyCard(
            accent: MistakeMapDesign.amber,
            children: [
              Text(item.subjectName),
              const SizedBox(height: 8),
              _StudyTitle(item.conceptName),
              const SizedBox(height: 8),
              Text(
                '${item.status == 'confirmed' ? 'Confirmado por você' : 'Sugestão'}: ${_categoryLabels[item.category] ?? item.category}',
              ),
              if (item.prompt.isNotEmpty) ...[
                const SizedBox(height: 16),
                SelectableText(item.prompt),
              ],
              const SizedBox(height: 16),
              SelectableText(item.evidence),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (item.status != 'confirmed')
                    _StudyButton(
                      label: 'Confirmar',
                      primary: true,
                      onPressed: _busy
                          ? null
                          : () => _decide(item, 'confirmed'),
                    ),
                  _StudyButton(
                    label: 'Corrigir',
                    onPressed: _busy ? null : () => _correct(item),
                  ),
                  _StudyButton(
                    label: 'Rejeitar',
                    onPressed: _busy ? null : () => _decide(item, 'rejected'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    ),
  );
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({required this.children, this.accent});
  final List<Widget> children;
  final Color? accent;
  @override
  Widget build(BuildContext context) => GlassSurface(
    padding: const EdgeInsets.all(24),
    accent: accent,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _StudyTitle extends StatelessWidget {
  const _StudyTitle(this.text, {this.large = false});
  final String text;
  final bool large;
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: TextStyle(
        fontSize: large ? 28 : 20,
        fontWeight: FontWeight.w600,
        color: MistakeMapDesign.abyss,
      ),
    ),
  );
}

class _StudyButton extends StatelessWidget {
  const _StudyButton({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
    child: MistakeMapButton(
      onPressed: onPressed,
      style: MistakeMapControls.button(
        background: primary ? MistakeMapDesign.aqua : MistakeMapDesign.white,
        foreground: primary ? MistakeMapDesign.abyss : MistakeMapDesign.content,
      ),
      child: Text(label, textAlign: TextAlign.center),
    ),
  );
}

/// Atalhos do fim do painel: lado a lado e centralizados quando cabem;
/// em tela estreita, empilhados e centralizados, Explorar conteúdos primeiro.
class _StudyActions extends StatelessWidget {
  const _StudyActions({required this.children});
  final List<Widget> children;

  static const _gap = 16.0;
  static const _width = 264.0;
  static const _maxStacked = 340.0;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitsInRow =
            constraints.maxWidth >=
            children.length * _width + (children.length - 1) * _gap;
        if (fitsInRow) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                SizedBox(width: _width, child: children[i]),
              ],
            ],
          );
        }
        final width = math.min(constraints.maxWidth, _maxStacked);
        return Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              SizedBox(width: width, child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Botão de atalho com ícone e acento Aurora; a tinta Abyss sobre o
/// preenchimento vivo mantém o contraste acima de 4,5:1.
class _StudyActionButton extends StatelessWidget {
  const _StudyActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 52),
    child: MistakeMapButton(
      onPressed: onPressed,
      style: MistakeMapControls.button(
        radius: 14,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        background: accent,
        foreground: MistakeMapDesign.abyss,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    ),
  );
}

class _StudyNotice extends StatelessWidget {
  const _StudyNotice(this.message, {this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: TextStyle(
        color: error ? MistakeMapDesign.bad : MistakeMapDesign.steel,
        fontSize: 16,
      ),
    ),
  );
}

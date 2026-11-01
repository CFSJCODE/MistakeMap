import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/design_tokens.dart';
import '../theme/motion.dart';
import 'analysis_models.dart';
import 'analysis_repository.dart';
import 'material_control_styles.dart';
import 'exercise_submission_view.dart';
import 'study_material.dart';
import 'study_material_view.dart';

class ErrorMapView extends StatefulWidget {
  final String userId;
  final AnalysisRepository repository;
  final VoidCallback? onClose;
  const ErrorMapView({
    super.key,
    required this.userId,
    required this.repository,
    this.onClose,
    this.startWithAnalysis = false,
    this.studyRepository,
  });

  /// Material de estudo (resumo, cartões e quiz). Sem ele, a página usa o
  /// cliente Supabase do repositório de análise, quando houver.
  final StudyMaterialRepository? studyRepository;

  /// Abre a página já com o formulário de análise expandido.
  final bool startWithAnalysis;

  @override
  State<ErrorMapView> createState() => _ErrorMapViewState();
}

class _ErrorMapViewState extends State<ErrorMapView> {
  late final StudyMaterialRepository? _study =
      widget.studyRepository ??
      switch (widget.repository) {
        final SupabaseAnalysisRepository supabase =>
          SupabaseStudyMaterialRepository(supabase.client),
        _ => null,
      };

  List<AttemptRecord> _attempts = [];
  bool _loading = true;
  String? _error;
  String? _subject;
  int _days = 0;
  int _view = 0;
  int _request = 0;
  final _analysis = ExpansibleController();
  final _analysisKey = GlobalKey();
  late bool _analysisOpen = widget.startWithAnalysis;

  // Botão flutuante e atalho do Início: abre o painel e rola até ele.
  void _openAnalysis() {
    if (!_analysis.isExpanded) _analysis.expand();
    // Rola depois da animação de abrir: antes dela a página ainda não tem a
    // altura do formulário e o painel ficaria cortado no rodapé.
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      final target = _analysisKey.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(target)
            ? Duration.zero
            : const Duration(milliseconds: 300),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    analysisChanges.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    analysisChanges.removeListener(_reload);
    _analysis.dispose();
    super.dispose();
  }

  // Mapa e análise na mesma página: o formulário de envio fica num painel
  // recolhível acima do mapa, aberto quando ainda não há tentativas.
  Widget _analysisSection() => Card(
    key: _analysisKey,
    margin: EdgeInsets.zero,
    color: mapSurface,
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: MistakeMapDesign.border),
    ),
    child: ExpansionTile(
      controller: _analysis,
      initiallyExpanded: widget.startWithAnalysis,
      onExpansionChanged: (open) => setState(() => _analysisOpen = open),
      // O formulário guarda o que já foi digitado ao recolher o painel.
      maintainState: true,
      leading: const Icon(Icons.lightbulb_outline, color: mapTitleBlue),
      title: const Text(
        'Analisar exercício com IA',
        style: TextStyle(color: mapTitleBlue, fontWeight: FontWeight.w600),
      ),
      subtitle: const Text(
        'Registre uma tentativa; a correção entra neste mapa.',
        style: TextStyle(color: mapContentBlue),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        ExerciseSubmissionView(
          userId: widget.userId,
          repository: widget.repository,
          embedded: true,
        ),
      ],
    ),
  );

  Future<void> _reload() async {
    final request = ++_request;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await widget.repository.loadAttempts(widget.userId);
      if (mounted && request == _request) {
        setState(() {
          _attempts = result;
          _loading = false;
        });
        // Sem tentativas o mapa não tem o que mostrar: começa pela análise.
        if (result.isEmpty && !_analysis.isExpanded) _analysis.expand();
        if (widget.startWithAnalysis && request == 1) _openAnalysis();
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _error = friendlyFailure(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _detail(AttemptRecord attempt) async {
    await Navigator.push(
      context,
      MistakeMapPageRoute<void>(
        context: context,
        builder: (_) => AttemptDetailView(
          userId: widget.userId,
          attemptId: attempt.id,
          repository: widget.repository,
          initialAttempt: attempt,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  void _evidence(String label, List<AttemptRecord> attempts) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '$label · ${attempts.length} tentativa(s)',
                  style: const TextStyle(
                    fontSize: 20,
                    color: mapTitleBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: attempts.length,
                  itemBuilder: (_, index) => AttemptTile(
                    attempt: attempts[index],
                    onTap: () {
                      Navigator.pop(ctx);
                      _detail(attempts[index]);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Estudar reúne resumo, cartões, quiz e a rodada de exercícios corrigidos
  /// pela IA; abre na matéria filtrada no mapa.
  void _openStudy(Map<String, String> subjects) {
    final study = _study;
    Navigator.push(
      context,
      MistakeMapPageRoute<void>(
        context: context,
        builder: (_) => study == null
            ? PracticeView(
                userId: widget.userId,
                repository: widget.repository,
                subjects: subjects,
              )
            : StudyMaterialView(
                repository: study,
                subjects: subjects,
                initialSubjectId: _subject,
                practiceBuilder: (subject) => PracticeView(
                  userId: widget.userId,
                  repository: widget.repository,
                  subjects: subjects,
                  initialSubjectId: subject,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjectNames = <String, String>{
      for (final a in _attempts) a.subjectId: a.subjectName,
    };
    final cutoff = DateTime.now().subtract(Duration(days: _days));
    final filtered = _attempts.where(
      (a) =>
          (_subject == null || a.subjectId == _subject) &&
          (_days == 0 || !a.attemptedAt.isBefore(cutoff)),
    );
    final insights = ErrorInsights.fromAttempts(filtered);
    return AuroraScaffold(
      appBar: AppBar(
        title: const Text('Mapa de erros'),
        foregroundColor: mapTitleBlue,
        leading: widget.onClose != null
            ? IconButton(
                tooltip: 'Voltar',
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onClose,
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Atualizar mapa',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _analysisOpen
          ? null
          : FloatingActionButton.extended(
              onPressed: _openAnalysis,
              backgroundColor: MistakeMapDesign.accent,
              foregroundColor: MistakeMapDesign.abyss,
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('Analisar exercício'),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          // Coluna, não ListView: uma lista preguiçosa descartaria o
          // formulário de análise ao rolar para o mapa.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  RetryMessage(message: _error!, retry: _reload)
                else if (_attempts.isEmpty) ...[
                  const SizedBox(height: 48),
                  const Icon(
                    Icons.account_tree_outlined,
                    size: 64,
                    color: MistakeMapDesign.violetInk,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Seu mapa ainda está vazio',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      color: mapTitleBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Analise um exercício abaixo para identificar suas fragilidades conceituais.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: mapContentBlue),
                  ),
                ] else ...[
                  _StudyCallout(
                    onStudy: () => _openStudy(subjectNames),
                    subjectName: subjectNames[_subject],
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<String>(
                    initialValue: _subject ?? '',
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(12),
                    dropdownColor: mapSurface,
                    menuMaxHeight: (MediaQuery.sizeOf(context).height * .5)
                        .clamp(160.0, 360.0),
                    decoration: const InputDecoration(labelText: 'Matéria'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Todas as matérias'),
                      ),
                      ...subjectNames.entries.map(
                        (s) => DropdownMenuItem(
                          value: s.key,
                          child: Text(s.value, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _subject = value == '' ? null : value),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final period in [
                        (0, 'Todo o histórico'),
                        (30, '30 dias'),
                        (7, '7 dias'),
                      ])
                        ChoiceChip(
                          label: Text(period.$2),
                          selected: _days == period.$1,
                          onSelected: (_) => setState(() => _days = period.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${insights.analyzedCount} análise(s) · ${insights.errorsCount} tentativa(s) com erros sugeridos pela IA',
                    style: const TextStyle(fontSize: 16, color: mapContentBlue),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'As frequências contam tentativas distintas. As classificações são sugestões da IA; toque para conferir os exercícios.',
                    style: TextStyle(fontSize: 14, color: mapContentBlue),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final view in [
                        (0, 'Gráficos'),
                        (1, 'Nuvem'),
                        (2, 'Conexões'),
                        (3, 'Tentativas'),
                      ])
                        ChoiceChip(
                          label: Text(view.$2),
                          selected: _view == view.$1,
                          onSelected: (_) => setState(() => _view = view.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (insights.attempts.isEmpty)
                    const Text('Nenhuma tentativa neste período.')
                  else if (_view == 3)
                    ...insights.attempts.map(
                      (a) => AttemptTile(attempt: a, onTap: () => _detail(a)),
                    )
                  else if (insights.categories.isEmpty) ...[
                    Text(
                      insights.analyzedCount == 0
                          ? 'As análises ainda não estão disponíveis. Abra uma tentativa para analisar ou tentar novamente.'
                          : 'Nenhum erro foi identificado nas análises deste período.',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => setState(() => _view = 3),
                      child: const Text('Ver tentativas'),
                    ),
                  ] else if (_view == 0) ...[
                    const SectionLabel('Tipos de erro'),
                    FrequencyBars(
                      values: insights.categories,
                      onTap: (count) => _evidence(
                        count.label,
                        insights.evidence(count.attemptIds),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SectionLabel('Matérias'),
                    FrequencyBars(
                      values: insights.subjects,
                      onTap: (count) => _evidence(
                        count.label,
                        insights.evidence(count.attemptIds),
                      ),
                    ),
                  ] else if (_view == 1) ...[
                    const SectionLabel('Conceitos com erros'),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: insights.concepts
                          .map(
                            (count) => TextButton(
                              onPressed: () => _evidence(
                                count.label,
                                insights.evidence(count.attemptIds),
                              ),
                              child: Text(
                                '${count.label} (${count.count})',
                                style: TextStyle(
                                  fontSize: insights.cloudFontSize(count.count),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ] else ...[
                    const SectionLabel('Matéria → conceito → tipo de erro'),
                    const Text(
                      'As linhas indicam ocorrência na mesma tentativa, sem inferir pré-requisitos. Amplie e arraste para explorar.',
                    ),
                    const SizedBox(height: 16),
                    ConceptGraph(
                      insights: insights,
                      onNode: (node) => _evidence(
                        node.label,
                        insights.evidence(node.attemptIds),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Bordas e linhas mais espessas têm mais tentativas. Os mesmos dados estão disponíveis na nuvem e nos gráficos.',
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                // A análise fica fora do carregamento do mapa: recarregar
                // depois de uma correção não descarta o formulário.
                _analysisSection(),
                // Espaço para o botão flutuante não cobrir o fim da página.
                const SizedBox(height: 72),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chamada principal do mapa: transformar os erros em estudo.
class _StudyCallout extends StatelessWidget {
  final VoidCallback onStudy;
  final String? subjectName;
  const _StudyCallout({required this.onStudy, this.subjectName});

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('map-study-callout'),
    color: mapSurface,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        spacing: 16,
        children: [
          const Icon(
            Icons.auto_stories_outlined,
            size: 32,
            color: MistakeMapDesign.violetInk,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                const Text(
                  'Estude seus pontos fracos',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: mapTitleBlue,
                  ),
                ),
                Text(
                  subjectName == null
                      ? 'Resumo, cartões, quiz e exercícios feitos a partir dos seus erros.'
                      : 'Resumo, cartões, quiz e exercícios de $subjectName.',
                ),
              ],
            ),
          ),
          FilledButton(
            key: const Key('open-study-material'),
            onPressed: onStudy,
            child: const Text('Estudar'),
          ),
        ],
      ),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        color: mapTitleBlue,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class FrequencyBars extends StatelessWidget {
  final List<InsightCount> values;
  final ValueChanged<InsightCount> onTap;
  const FrequencyBars({super.key, required this.values, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final highest = values.fold<int>(1, (n, e) => math.max(n, e.count));
    return Column(
      children: values
          .map(
            (value) => TextButton(
              style:
                  MistakeMapMaterialControls.button(
                    context,
                    background: Colors.transparent,
                    quiet: true,
                  ).copyWith(
                    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                    textStyle: const WidgetStatePropertyAll(
                      TextStyle(fontSize: 14),
                    ),
                  ),
              onPressed: () => onTap(value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Semantics(
                  button: true,
                  label:
                      '${value.label}: ${value.count} tentativas. Ver evidências.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(value.label)),
                          Text('${value.count}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Barra no violeta da IA: a frequência é uma leitura
                      // do Mapa, e o rótulo ao lado já traz o número.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: value.count / highest,
                          minHeight: 12,
                          backgroundColor: const Color(0xB3FFFFFF),
                          color: MistakeMapDesign.violet,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class ConceptGraph extends StatefulWidget {
  final ErrorInsights insights;
  final ValueChanged<GraphNode> onNode;
  const ConceptGraph({super.key, required this.insights, required this.onNode});

  @override
  State<ConceptGraph> createState() => _ConceptGraphState();
}

class _ConceptGraphState extends State<ConceptGraph> {
  final _transform = TransformationController();
  double? _width;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width - 48;
    if (_width != width) {
      _width = width;
      _transform.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insights = widget.insights;
    final graphWidth = math.max(312.0, math.min(900.0, _width ?? 680));
    final nodeWidth = math.min(176.0, graphWidth / 3 - 16);
    final groups = ['Matéria', 'Conceito', 'Tipo de erro']
        .map((kind) => insights.nodes.where((n) => n.kind == kind).toList())
        .toList();
    final height = math.max(
      360.0,
      groups.fold<int>(0, (v, e) => math.max(v, e.length)) * 96.0 + 64,
    );
    final points = <String, Offset>{};
    for (var column = 0; column < groups.length; column++) {
      for (var row = 0; row < groups[column].length; row++) {
        points[groups[column][row].id] = Offset(
          (column + .5) * graphWidth / 3,
          48 + (height - 96) * (row + .5) / groups[column].length,
        );
      }
    }
    return SizedBox(
      height: 400,
      child: ClipRect(
        child: InteractiveViewer(
          transformationController: _transform,
          constrained: false,
          minScale: .8,
          maxScale: 3,
          boundaryMargin: const EdgeInsets.all(48),
          child: SizedBox(
            width: graphWidth,
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GraphPainter(points, insights.edges),
                  ),
                ),
                for (final node in insights.nodes)
                  Positioned(
                    left: points[node.id]!.dx - nodeWidth / 2,
                    top: points[node.id]!.dy - 36,
                    width: nodeWidth,
                    height: 72,
                    child: Tooltip(
                      message:
                          '${node.kind}: ${node.label}. ${node.attemptIds.length} tentativa(s)',
                      child: OutlinedButton(
                        onPressed: () => widget.onNode(node),
                        style:
                            MistakeMapMaterialControls.button(
                              context,
                              background: Colors.white,
                              radius: 10,
                              border: BorderSide(
                                color: node.kind == 'Conceito'
                                    ? MistakeMapDesign.violetInk
                                    : MistakeMapDesign.azureInk,
                                width:
                                    1 + math.min(3, node.attemptIds.length) / 2,
                              ),
                            ).copyWith(
                              padding: const WidgetStatePropertyAll(
                                EdgeInsets.all(8),
                              ),
                            ),
                        child: Text(
                          '${node.label}\n${node.attemptIds.length} tentativa(s)',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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

class _GraphPainter extends CustomPainter {
  final Map<String, Offset> points;
  final List<GraphEdge> edges;
  _GraphPainter(this.points, this.edges);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = mapContentBlue.withValues(alpha: .35);
    for (final edge in edges) {
      final from = points[edge.from];
      final to = points[edge.to];
      if (from != null && to != null) {
        paint.strokeWidth = 1 + math.min(4, edge.attemptIds.length).toDouble();
        canvas.drawLine(from, to, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) =>
      old.points != points || old.edges != edges;
}

class AttemptTile extends StatelessWidget {
  final AttemptRecord attempt;
  final VoidCallback onTap;
  const AttemptTile({super.key, required this.attempt, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    child: TextButton(
      style: MistakeMapMaterialControls.button(
        context,
        background: Colors.white,
        radius: 12,
        border: BorderSide.none,
      ).copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.zero)),
      onPressed: onTap,
      child: ListTile(
        title: Text(
          attempt.prompt,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('${attempt.subjectName} · ${attempt.statusLabel}'),
        trailing: const Icon(Icons.chevron_right),
      ),
    ),
  );
}

class RetryMessage extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const RetryMessage({super.key, required this.message, required this.retry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    ),
  );
}

class AttemptDetailView extends StatefulWidget {
  final String userId;
  final String attemptId;
  final AnalysisRepository repository;
  final AttemptRecord? initialAttempt;
  const AttemptDetailView({
    super.key,
    required this.userId,
    required this.attemptId,
    required this.repository,
    this.initialAttempt,
  });
  @override
  State<AttemptDetailView> createState() => _AttemptDetailViewState();
}

class _AttemptDetailViewState extends State<AttemptDetailView> {
  AttemptRecord? _attempt;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _attempt = widget.initialAttempt;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final attempts = await widget.repository.loadAttempts(widget.userId);
      final matches = attempts.where((a) => a.id == widget.attemptId);
      if (!mounted) return;
      setState(() {
        _attempt = matches.isEmpty ? null : matches.first;
        if (_attempt == null) _error = 'Esta tentativa não está disponível.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyFailure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.analyze(widget.attemptId);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = friendlyFailure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resumeUpload() async {
    if (_busy) return;
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2048,
      );
      if (image == null || !mounted) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      await widget.repository.uploadImage(
        widget.attemptId,
        image.name,
        await image.readAsBytes(),
      );
      await widget.repository.analyze(widget.attemptId);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = friendlyFailure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attempt = _attempt;
    final analysis = attempt?.analysis;
    return AuroraScaffold(
      appBar: AppBar(
        title: const Text('Correção e evidências'),
        foregroundColor: mapTitleBlue,
        actions: [
          IconButton(
            tooltip: 'Atualizar tentativa',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: MistakeMapDesign.bad),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (attempt != null) ...[
              Text(
                '${attempt.subjectName} · ${attempt.statusLabel}',
                style: const TextStyle(color: mapContentBlue),
              ),
              const SizedBox(height: 24),
              const SectionLabel('Enunciado'),
              SelectableText(attempt.prompt),
              const SizedBox(height: 24),
              const SectionLabel('Sua resposta'),
              SelectableText(attempt.answer),
              const SizedBox(height: 24),
              if (analysis == null) ...[
                const Text('A correção ainda não está disponível.'),
                const SizedBox(height: 16),
                if (attempt.status == 'uploading') ...[
                  const Text(
                    'O envio da foto ainda não terminou. Selecione novamente a foto desta tentativa.',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _resumeUpload,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Reenviar foto e analisar'),
                  ),
                ] else if (attempt.status == 'dead_letter' ||
                    attempt.status == 'cancelled')
                  const Text(
                    'Esta tentativa foi encerrada. Registre uma nova tentativa para continuar.',
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _analyze,
                    icon: const Icon(Icons.psychology_outlined),
                    label: const Text('Analisar tentativa'),
                  ),
              ] else ...[
                Text(
                  analysis.isCorrect == null
                      ? 'A IA precisa de revisão dos dados fornecidos.'
                      : analysis.isCorrect!
                      ? 'A IA considerou sua resposta correta.'
                      : 'A IA identificou pontos a corrigir.',
                  style: const TextStyle(
                    fontSize: 18,
                    color: mapTitleBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                if (analysis.correctAnswer.isNotEmpty) ...[
                  const SectionLabel('Resposta sugerida'),
                  SelectableText(analysis.correctAnswer),
                  const SizedBox(height: 24),
                ],
                const SectionLabel('Explicação'),
                SelectableText(analysis.explanation),
                if (analysis.transcribedPrompt.isNotEmpty ||
                    analysis.transcribedAnswer.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  ExpansionTile(
                    title: const Text('Conferir transcrição da foto'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          'Enunciado: ${analysis.transcribedPrompt}\n\nResposta: ${analysis.transcribedAnswer}',
                        ),
                      ),
                    ],
                  ),
                ],
                for (final error in analysis.errors) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${error.label} · ${error.concept}',
                            style: const TextStyle(
                              fontSize: 18,
                              color: mapContentBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(error.evidence),
                          const SizedBox(height: 8),
                          Text(
                            'Confiança declarada pela IA: ${(error.confidence * 100).round()}%',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Esta análise é uma sugestão da IA. Ela pode conter erros; confira os passos e o enunciado.',
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MistakeMapPageRoute<void>(
                            context: context,
                            builder: (_) => PracticeView(
                              userId: widget.userId,
                              repository: widget.repository,
                              subjects: {
                                attempt.subjectId: attempt.subjectName,
                              },
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.school_outlined),
                  label: const Text('Gerar exercícios para praticar'),
                ),
              ],
            ] else if (!_busy)
              OutlinedButton(onPressed: _load, child: const Text('Atualizar')),
          ],
        ),
      ),
    );
  }
}

class PracticeView extends StatefulWidget {
  final String userId;
  final AnalysisRepository repository;
  final Map<String, String> subjects;
  const PracticeView({
    super.key,
    required this.userId,
    required this.repository,
    required this.subjects,
    this.initialSubjectId,
  });

  /// Matéria já escolhida ao abrir (por exemplo, a filtrada no mapa).
  final String? initialSubjectId;
  @override
  State<PracticeView> createState() => _PracticeViewState();
}

class _PracticeViewState extends State<PracticeView> {
  String? _subject;
  String? _category;
  int _count = 3;
  bool _busy = false;
  String? _error;
  List<PracticeExercise> _exercises = [];

  /// The last generated batch, answered one question at a time.
  List<PracticeExercise> _roundExercises = [];
  List<PracticeRoundEntry> _roundEntries = [];
  bool _roundStarted = false;
  bool _roundBusy = false;

  bool get _roundActive =>
      _roundStarted && _roundEntries.length < _roundExercises.length;
  bool get _roundComplete =>
      _roundExercises.isNotEmpty &&
      _roundEntries.length == _roundExercises.length;

  @override
  void initState() {
    super.initState();
    _subject = widget.subjects.containsKey(widget.initialSubjectId)
        ? widget.initialSubjectId
        : widget.subjects.keys.firstOrNull;
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final existing = await widget.repository.loadPractice(widget.userId);
      if (mounted) setState(() => _exercises = existing);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyFailure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() async {
    if (_subject == null || _busy || _roundBusy || _roundActive) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.generatePractice(
        _subject!,
        widget.subjects[_subject]!,
        _count,
        category: _category,
      );
      if (!mounted) return;
      if (result.isEmpty) {
        setState(
          () => _error = 'Nenhum exercício foi gerado. Tente novamente.',
        );
        return;
      }
      setState(() {
        _exercises = [...result, ..._exercises];
        _roundExercises = result;
        _roundEntries = [];
        _roundStarted = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyFailure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the answer form; resolves to the analysed attempt's ID, or null
  /// when the student left without an analysis (back button, offline queue).
  Future<String?> _openExercise(PracticeExercise exercise) =>
      Navigator.of(context).push<String>(
        MistakeMapPageRoute<String>(
          context: context,
          builder: (_) => ExerciseSubmissionView(
            userId: widget.userId,
            repository: widget.repository,
            practice: exercise,
          ),
        ),
      );

  Future<void> _answerRoundQuestion() async {
    if (_roundBusy || !_roundActive) return;
    final exercise = _roundExercises[_roundEntries.length];
    setState(() {
      _roundBusy = true;
      _error = null;
    });
    try {
      final attemptId = await _openExercise(exercise);
      if (attemptId == null || !mounted) return;
      final attempts = await widget.repository.loadAttempts(widget.userId);
      final attempt = attempts
          .where((item) => item.id == attemptId && item.analysis != null)
          .firstOrNull;
      if (!mounted) return;
      setState(() {
        if (attempt == null) {
          _error =
              'Não foi possível confirmar a análise desta resposta. '
              'A rodada continua nesta questão.';
        } else {
          _roundEntries = [
            ..._roundEntries,
            PracticeRoundEntry(exercise: exercise, attempt: attempt),
          ];
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyFailure(error));
    } finally {
      if (mounted) setState(() => _roundBusy = false);
    }
  }

  Widget _roundMetric(String label, int count, double? percentage) => SizedBox(
    width: 96,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: MistakeMapDesign.steel)),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: mapTitleBlue,
          ),
        ),
        Text(
          percentage == null ? '—' : '${percentage.toStringAsFixed(0)}%',
          style: const TextStyle(color: MistakeMapDesign.steel),
        ),
      ],
    ),
  );

  Widget _roundCard({
    required Key key,
    required String title,
    required List<Widget> children,
  }) => Card(
    key: key,
    color: mapSurface,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: mapTitleBlue,
            ),
          ),
          ...children,
        ],
      ),
    ),
  );

  Widget _roundSetupCard() => _roundCard(
    key: const Key('practice-round-setup'),
    title: 'Rodada pronta',
    children: [
      Text(
        '${_roundExercises.length} exercícios. As métricas serão calculadas '
        'depois da análise de cada resposta.',
      ),
      ElevatedButton.icon(
        key: const Key('practice-round-start'),
        onPressed: _busy ? null : () => setState(() => _roundStarted = true),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Iniciar rodada'),
      ),
    ],
  );

  Widget _roundProgressCard() {
    final answered = _roundEntries.length;
    final exercise = _roundExercises[answered];
    return _roundCard(
      key: const Key('practice-round-progress'),
      title: 'Questão ${answered + 1} de ${_roundExercises.length}',
      children: [
        LinearProgressIndicator(value: answered / _roundExercises.length),
        Text(
          exercise.focusConcept.isEmpty
              ? exercise.prompt
              : '${exercise.focusConcept}\n\n${exercise.prompt}',
          style: const TextStyle(fontSize: 16),
        ),
        ElevatedButton.icon(
          key: const Key('practice-round-resolve'),
          onPressed: _roundBusy ? null : _answerRoundQuestion,
          icon: const Icon(Icons.edit_outlined),
          label: Text(_roundBusy ? 'Analisando resposta…' : 'Responder'),
        ),
      ],
    );
  }

  Widget _roundSummaryCard() {
    final summary = PracticeRoundSummary(_roundEntries);
    final missed = summary.mostMissedConcepts;
    return _roundCard(
      key: const Key('practice-round-summary'),
      title: 'Resumo da rodada',
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _roundMetric(
              'Acertos',
              summary.correctCount,
              summary.correctPercentage,
            ),
            _roundMetric(
              'Erros',
              summary.incorrectCount,
              summary.incorrectPercentage,
            ),
            _roundMetric('Inconclusivas', summary.inconclusiveCount, null),
          ],
        ),
        Text(
          summary.assessedCount == 0
              ? 'A IA não conseguiu classificar respostas nesta rodada; '
                    'não há percentual de acerto calculável.'
              : 'Percentuais calculados sobre ${summary.assessedCount} '
                    'resposta(s) classificadas. Inconclusivas ficam fora do cálculo.',
        ),
        const Text(
          'Assuntos mais errados',
          style: TextStyle(fontWeight: FontWeight.w600, color: mapTitleBlue),
        ),
        if (missed.isEmpty)
          const Text('Nenhum assunto incorreto foi identificado nesta rodada.')
        else
          for (final concept in missed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bubble_chart_outlined),
              title: Text(concept.label),
              trailing: Text('${concept.count} questão(ões)'),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controlsDisabled = _busy || _roundBusy || _roundActive;

    return AuroraScaffold(
      appBar: AppBar(
        title: const Text('Praticar meus erros'),
        foregroundColor: mapTitleBlue,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'A IA gera exercícios personalizados com base nos seus erros nesta matéria, '
              'priorizando os conceitos que você errou mais vezes e mais recentemente. '
              'Conceitos que você já voltou a acertar perdem prioridade. Sem histórico, '
              'a IA gera questões diagnósticas. Respostas antigas ainda sem análise '
              'serão avaliadas antes da geração.',
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: _subject,
              isExpanded: true,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: mapSurface,
              menuMaxHeight: (MediaQuery.sizeOf(context).height * .5).clamp(
                160.0,
                360.0,
              ),
              decoration: const InputDecoration(labelText: 'Matéria'),
              items: widget.subjects.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: controlsDisabled
                  ? null
                  : (value) => setState(() => _subject = value),
            ),
            const SizedBox(height: 16),
            const Text('Tipo de erro para reforçar'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('practice-category-all'),
                  label: const Text('Todos os tipos'),
                  selected: _category == null,
                  onSelected: controlsDisabled
                      ? null
                      : (_) => setState(() => _category = null),
                ),
                for (final entry in categoryLabels.entries)
                  ChoiceChip(
                    key: Key('practice-category-${entry.key}'),
                    label: Text(entry.value),
                    selected: _category == entry.key,
                    onSelected: controlsDisabled
                        ? null
                        : (_) => setState(() => _category = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final count in [3, 4, 5])
                  ChoiceChip(
                    label: Text('$count exercícios'),
                    selected: count == _count,
                    onSelected: controlsDisabled
                        ? null
                        : (_) => setState(() => _count = count),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: controlsDisabled || _subject == null
                  ? null
                  : _generate,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(
                _busy
                    ? 'Preparando exercícios…'
                    : _roundComplete
                    ? 'Gerar nova rodada'
                    : 'Gerar exercícios',
              ),
            ),
            if (_busy || _roundBusy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(color: MistakeMapDesign.bad),
                  ),
                ),
              ),
            if (_roundExercises.firstOrNull?.subjectId == _subject)
              if (!_roundStarted)
                _roundSetupCard()
              else if (_roundActive)
                _roundProgressCard()
              else
                _roundSummaryCard(),
            for (var index = 0; index < _exercises.length; index++)
              if (_exercises[index].subjectId == _subject)
                Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Exercício ${index + 1}${_exercises[index].focusConcept.isEmpty ? '' : ' · ${_exercises[index].focusConcept}'}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: mapTitleBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(_exercises[index].prompt),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: controlsDisabled
                              ? null
                              : () => _openExercise(_exercises[index]),
                          child: const Text('Resolver'),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

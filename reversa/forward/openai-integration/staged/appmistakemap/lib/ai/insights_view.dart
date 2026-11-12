import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'analysis_models.dart';
import 'analysis_repository.dart';
import 'exercise_submission_view.dart';

class ErrorMapView extends StatefulWidget {
  final String userId;
  final AnalysisRepository repository;
  const ErrorMapView({
    super.key,
    required this.userId,
    required this.repository,
  });

  @override
  State<ErrorMapView> createState() => _ErrorMapViewState();
}

class _ErrorMapViewState extends State<ErrorMapView> {
  List<AttemptRecord> _attempts = [];
  bool _loading = true;
  String? _error;
  String? _subject;
  int _days = 0;
  int _view = 0;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    analysisChanges.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    analysisChanges.removeListener(_reload);
    super.dispose();
  }

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
      MaterialPageRoute<void>(
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de erros'),
        backgroundColor: mapSurface,
        foregroundColor: mapTitleBlue,
        actions: [
          IconButton(
            tooltip: 'Atualizar mapa',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      backgroundColor: mapBackground,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? RetryMessage(message: _error!, retry: _reload)
            : RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (_attempts.isEmpty) ...[
                      const SizedBox(height: 48),
                      const Icon(
                        Icons.account_tree_outlined,
                        size: 64,
                        color: mapContentBlue,
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
                        'Adicione exercícios para identificar suas fragilidades conceituais.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: mapContentBlue),
                      ),
                    ] else ...[
                      DropdownButtonFormField<String>(
                        initialValue: _subject ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Matéria',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Todas as matérias'),
                          ),
                          ...subjectNames.entries.map(
                            (s) => DropdownMenuItem(
                              value: s.key,
                              child: Text(
                                s.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _subject = value == '' ? null : value,
                        ),
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
                              onSelected: (_) =>
                                  setState(() => _days = period.$1),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${insights.analyzedCount} análise(s) · ${insights.errorsCount} tentativa(s) com erros sugeridos pela IA',
                        style: const TextStyle(
                          fontSize: 16,
                          color: mapContentBlue,
                        ),
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
                              onSelected: (_) =>
                                  setState(() => _view = view.$1),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (insights.attempts.isEmpty)
                        const Text('Nenhuma tentativa neste período.')
                      else if (_view == 3)
                        ...insights.attempts.map(
                          (a) =>
                              AttemptTile(attempt: a, onTap: () => _detail(a)),
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
                                      fontSize: insights.cloudFontSize(
                                        count.count,
                                      ),
                                      color: mapContentBlue,
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
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => PracticeView(
                              userId: widget.userId,
                              repository: widget.repository,
                              subjects: subjectNames,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.school_outlined),
                        label: const Text(
                          'Praticar meus pontos de dificuldade',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
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
            (value) => InkWell(
              onTap: () => onTap(value),
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
                      LinearProgressIndicator(
                        value: value.count / highest,
                        minHeight: 12,
                        backgroundColor: mapSurface,
                        color: mapContentBlue,
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
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: mapContentBlue,
                          padding: const EdgeInsets.all(8),
                          side: BorderSide(
                            color: node.kind == 'Conceito'
                                ? mapTitleBlue
                                : mapContentBlue,
                            width: 1 + math.min(3, node.attemptIds.length) / 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
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
    child: ListTile(
      title: Text(attempt.prompt, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${attempt.subjectName} · ${attempt.statusLabel}'),
      trailing: const Icon(Icons.chevron_right, color: mapContentBlue),
      onTap: onTap,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Correção e evidências'),
        backgroundColor: mapSurface,
        foregroundColor: mapTitleBlue,
        actions: [
          IconButton(
            tooltip: 'Atualizar tentativa',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      backgroundColor: mapBackground,
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
                  style: TextStyle(color: Colors.red.shade700),
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
                          MaterialPageRoute<void>(
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
  });
  @override
  State<PracticeView> createState() => _PracticeViewState();
}

class _PracticeViewState extends State<PracticeView> {
  String? _subject;
  int _count = 3;
  bool _busy = false;
  String? _error;
  List<PracticeExercise> _exercises = [];
  @override
  void initState() {
    super.initState();
    _subject = widget.subjects.keys.firstOrNull;
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
    if (_subject == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.generatePractice(
        _subject!,
        widget.subjects[_subject]!,
        _count,
      );
      if (mounted) setState(() => _exercises = [...result, ..._exercises]);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyFailure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Praticar meus erros'),
      backgroundColor: mapSurface,
      foregroundColor: mapTitleBlue,
    ),
    backgroundColor: mapBackground,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'A IA usa as dificuldades identificadas nesta matéria para propor novos exercícios.',
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: _subject,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Matéria',
              border: OutlineInputBorder(),
            ),
            items: widget.subjects.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() => _subject = value),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final count in [3, 4, 5])
                ChoiceChip(
                  label: Text('$count exercícios'),
                  selected: count == _count,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _count = count),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _busy || _subject == null ? null : _generate,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(_busy ? 'Gerando exercícios…' : 'Gerar exercícios'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ),
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
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ExerciseSubmissionView(
                              userId: widget.userId,
                              repository: widget.repository,
                              practice: _exercises[index],
                            ),
                          ),
                        ),
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

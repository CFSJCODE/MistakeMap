import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import 'analysis_repository.dart' show friendlyFailure;
import 'exercise_submission_view.dart';
import 'study_material.dart';

/// Material de estudo no estilo caderno guiado: resumo, flashcards e quiz
/// gerados pela IA a partir dos exercícios e erros da matéria.
class StudyMaterialView extends StatefulWidget {
  final StudyMaterialRepository repository;
  final Map<String, String> subjects;
  final String? initialSubjectId;

  const StudyMaterialView({
    super.key,
    required this.repository,
    required this.subjects,
    this.initialSubjectId,
  });

  @override
  State<StudyMaterialView> createState() => _StudyMaterialViewState();
}

enum _StudyTab { summary, flashcards, quiz }

class _StudyMaterialViewState extends State<StudyMaterialView> {
  String? _subject;
  bool _loading = true;
  bool _generating = false;
  String? _error;
  List<StudyMaterial> _materials = [];
  String? _openMaterialId;
  _StudyTab _tab = _StudyTab.summary;

  @override
  void initState() {
    super.initState();
    _subject = widget.subjects.containsKey(widget.initialSubjectId)
        ? widget.initialSubjectId
        : widget.subjects.keys.firstOrNull;
    _load();
  }

  List<StudyMaterial> get _subjectMaterials =>
      _materials.where((m) => m.subjectId == _subject).toList();

  StudyMaterial? get _open {
    final materials = _subjectMaterials;
    return materials.where((m) => m.id == _openMaterialId).firstOrNull ??
        materials.firstOrNull;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final materials = await widget.repository.loadMaterials(widget.subjects);
      if (mounted) setState(() => _materials = materials);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyFailure(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    final subject = _subject;
    if (subject == null || _generating) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final material = await widget.repository.generate(
        subject,
        widget.subjects[subject]!,
      );
      if (!mounted) return;
      setState(() {
        _materials = [material, ..._materials];
        _openMaterialId = material.id;
        _tab = _StudyTab.summary;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyFailure(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final material = _open;
    final history = _subjectMaterials;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estudar com a IA'),
        backgroundColor: mapSurface,
        foregroundColor: mapTitleBlue,
      ),
      backgroundColor: mapBackground,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'A IA lê os exercícios que você registrou e os erros que ela '
              'identificou nesta matéria e monta um resumo, flashcards e um '
              'quiz de múltipla escolha. O gabarito só aparece depois que você '
              'responde.',
            ),
            const SizedBox(height: 24),
            if (widget.subjects.isEmpty)
              const _StudyEmptyState(
                key: Key('study-no-subjects'),
                icon: Icons.menu_book_outlined,
                title: 'Nenhuma matéria ainda',
                message:
                    'Registre um exercício com a matéria dele. O material de '
                    'estudo é montado a partir do que você já resolveu.',
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _subject,
                isExpanded: true,
                borderRadius: BorderRadius.circular(12),
                dropdownColor: mapSurface,
                decoration: const InputDecoration(labelText: 'Matéria'),
                items: [
                  for (final entry in widget.subjects.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _generating
                    ? null
                    : (value) => setState(() {
                        _subject = value;
                        _openMaterialId = null;
                        _tab = _StudyTab.summary;
                      }),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                key: const Key('study-generate'),
                onPressed: _generating || _subject == null ? null : _generate,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(
                  _generating
                      ? 'Montando seu material…'
                      : material == null
                      ? 'Gerar material de estudo'
                      : 'Gerar novo material',
                ),
              ),
              if (_generating || _loading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: MistakeMapDesign.bad),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (material != null) ...[
                _materialHeader(material, history),
                const SizedBox(height: 16),
                SegmentedButton<_StudyTab>(
                  key: const Key('study-tabs'),
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(
                      value: _StudyTab.summary,
                      icon: Icon(Icons.article_outlined),
                      label: Text('Resumo'),
                    ),
                    ButtonSegment(
                      value: _StudyTab.flashcards,
                      icon: const Icon(Icons.style_outlined),
                      label: Text('Cartões (${material.flashcards.length})'),
                    ),
                    ButtonSegment(
                      value: _StudyTab.quiz,
                      icon: const Icon(Icons.quiz_outlined),
                      label: Text('Quiz (${material.quiz.length})'),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (value) =>
                      setState(() => _tab = value.first),
                ),
                const SizedBox(height: 16),
                switch (_tab) {
                  _StudyTab.summary => _SummaryPanel(material.summary),
                  _StudyTab.flashcards => FlashcardDeck(
                    key: ValueKey('deck-${material.id}'),
                    cards: material.flashcards,
                  ),
                  _StudyTab.quiz => QuizPanel(
                    key: ValueKey('quiz-${material.id}'),
                    material: material,
                    repository: widget.repository,
                  ),
                },
              ] else if (!_loading && !_generating)
                const _StudyEmptyState(
                  key: Key('study-empty'),
                  icon: Icons.auto_stories_outlined,
                  title: 'Seu primeiro material',
                  message:
                      'Toque em “Gerar material de estudo”. Quanto mais '
                      'exercícios você registrar, mais o material se parece '
                      'com as suas dificuldades.',
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _materialHeader(StudyMaterial material, List<StudyMaterial> history) {
    final local = MaterialLocalizations.of(context);
    String label(StudyMaterial m) =>
        '${local.formatMediumDate(m.createdAt)} · '
        '${local.formatTimeOfDay(TimeOfDay.fromDateTime(m.createdAt))}';
    return Row(
      children: [
        Expanded(
          child: Text(
            material.sourceCount > 0
                ? 'Baseado em ${material.sourceCount} exercício(s) seus.'
                : 'Material introdutório: ainda há poucos exercícios '
                      'registrados nesta matéria.',
            style: const TextStyle(color: MistakeMapDesign.steel),
          ),
        ),
        if (history.length > 1)
          PopupMenuButton<String>(
            key: const Key('study-history'),
            tooltip: 'Materiais anteriores',
            icon: const Icon(Icons.history),
            onSelected: (id) => setState(() {
              _openMaterialId = id;
              _tab = _StudyTab.summary;
            }),
            itemBuilder: (_) => [
              for (final item in history)
                CheckedPopupMenuItem(
                  value: item.id,
                  checked: item.id == material.id,
                  child: Text(label(item)),
                ),
            ],
          ),
      ],
    );
  }
}

class _StudyEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _StudyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Card(
    color: mapSurface,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        spacing: 12,
        children: [
          Icon(icon, size: 40, color: mapTitleBlue),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: mapTitleBlue,
            ),
          ),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

Widget _panel({required List<Widget> children, Key? key}) => Card(
  key: key,
  color: mapSurface,
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: children,
    ),
  ),
);

const _panelTitle = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w600,
  color: mapTitleBlue,
);

class _SummaryPanel extends StatelessWidget {
  final StudySummary summary;
  const _SummaryPanel(this.summary);

  Widget _bullets(List<String> items, IconData icon) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      for (final item in items)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: mapTitleBlue),
            ),
            Expanded(child: Text(item)),
          ],
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) {
      return _panel(
        key: const Key('study-summary'),
        children: const [Text('A IA não devolveu um resumo neste material.')],
      );
    }
    return _panel(
      key: const Key('study-summary'),
      children: [
        Text(summary.title, style: _panelTitle),
        if (summary.overview.isNotEmpty) Text(summary.overview),
        if (summary.keyPoints.isNotEmpty) ...[
          const Text(
            'Pontos-chave',
            style: TextStyle(fontWeight: FontWeight.w600, color: mapTitleBlue),
          ),
          _bullets(summary.keyPoints, Icons.check_circle_outline),
        ],
        if (summary.commonMistakes.isNotEmpty) ...[
          const Text(
            'Onde você costuma errar',
            style: TextStyle(fontWeight: FontWeight.w600, color: mapTitleBlue),
          ),
          _bullets(summary.commonMistakes, Icons.warning_amber_outlined),
        ],
      ],
    );
  }
}

/// Baralho de revisão: toque vira o cartão; o estudante marca se já sabia.
class FlashcardDeck extends StatefulWidget {
  final List<Flashcard> cards;
  const FlashcardDeck({super.key, required this.cards});

  @override
  State<FlashcardDeck> createState() => _FlashcardDeckState();
}

class _FlashcardDeckState extends State<FlashcardDeck> {
  late List<Flashcard> _deck = widget.cards;
  int _index = 0;
  bool _flipped = false;
  final List<Flashcard> _unknown = [];
  int _known = 0;

  bool get _finished => _index >= _deck.length;

  void _mark({required bool known}) => setState(() {
    if (known) {
      _known++;
    } else {
      _unknown.add(_deck[_index]);
    }
    _index++;
    _flipped = false;
  });

  void _restart(List<Flashcard> deck) => setState(() {
    _deck = deck;
    _index = 0;
    _flipped = false;
    _known = 0;
    _unknown.clear();
  });

  @override
  Widget build(BuildContext context) {
    if (_deck.isEmpty) {
      return _panel(
        key: const Key('study-flashcards'),
        children: const [Text('Este material não tem cartões.')],
      );
    }
    if (_finished) {
      final review = List<Flashcard>.of(_unknown);
      return _panel(
        key: const Key('study-flashcards-done'),
        children: [
          const Text('Revisão concluída', style: _panelTitle),
          Text('Você já sabia $_known de ${_deck.length} cartão(ões).'),
          if (review.isNotEmpty)
            ElevatedButton.icon(
              key: const Key('flashcards-review-unknown'),
              onPressed: () => _restart(review),
              icon: const Icon(Icons.replay),
              label: Text('Revisar os ${review.length} que faltaram'),
            ),
          OutlinedButton(
            onPressed: () => _restart(widget.cards),
            child: const Text('Recomeçar o baralho'),
          ),
        ],
      );
    }
    final card = _deck[_index];
    return _panel(
      key: const Key('study-flashcards'),
      children: [
        Text(
          'Cartão ${_index + 1} de ${_deck.length}'
          '${card.concept.isEmpty ? '' : ' · ${card.concept}'}',
          style: const TextStyle(color: MistakeMapDesign.steel),
        ),
        LinearProgressIndicator(value: _index / _deck.length),
        Semantics(
          button: true,
          label: _flipped ? 'Resposta. Toque para ver a pergunta' : null,
          child: InkWell(
            key: const Key('flashcard-face'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _flipped = !_flipped),
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: Container(
                key: ValueKey(_flipped),
                constraints: const BoxConstraints(minHeight: 160),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _flipped ? mapBackground : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MistakeMapDesign.mist),
                ),
                child: Text(
                  _flipped ? card.back : card.front,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _flipped ? 16 : 18,
                    fontWeight: _flipped ? FontWeight.w400 : FontWeight.w600,
                    color: mapTitleBlue,
                  ),
                ),
              ),
            ),
          ),
        ),
        Text(
          _flipped
              ? 'Você sabia a resposta?'
              : 'Toque no cartão para ver a resposta.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: MistakeMapDesign.steel),
        ),
        if (_flipped)
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('flashcard-unknown'),
                  onPressed: () => _mark(known: false),
                  child: const Text('Ainda não'),
                ),
              ),
              Expanded(
                child: ElevatedButton(
                  key: const Key('flashcard-known'),
                  onPressed: () => _mark(known: true),
                  child: const Text('Já sabia'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Quiz de múltipla escolha, uma questão por vez, corrigido no servidor.
class QuizPanel extends StatefulWidget {
  final StudyMaterial material;
  final StudyMaterialRepository repository;
  const QuizPanel({
    super.key,
    required this.material,
    required this.repository,
  });

  @override
  State<QuizPanel> createState() => _QuizPanelState();
}

class _QuizPanelState extends State<QuizPanel> {
  final Map<String, int> _answers = {};
  int _index = 0;
  bool _grading = false;
  String? _error;
  QuizRoundResult? _result;

  List<QuizQuestion> get _quiz => widget.material.quiz;

  Future<void> _grade() async {
    if (_grading) return;
    setState(() {
      _grading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.gradeQuiz(
        widget.material.id,
        Map.of(_answers),
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyFailure(error));
    } finally {
      if (mounted) setState(() => _grading = false);
    }
  }

  void _restart() => setState(() {
    _answers.clear();
    _index = 0;
    _result = null;
    _error = null;
  });

  Widget _metric(String label, String value, String? detail) => SizedBox(
    width: 96,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: MistakeMapDesign.steel)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: mapTitleBlue,
          ),
        ),
        if (detail != null)
          Text(detail, style: const TextStyle(color: MistakeMapDesign.steel)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_quiz.isEmpty) {
      return _panel(
        key: const Key('study-quiz'),
        children: const [Text('Este material não tem questões de quiz.')],
      );
    }
    final result = _result;
    if (result != null) return _summary(result);

    final question = _quiz[_index];
    final chosen = _answers[question.id];
    final last = _index == _quiz.length - 1;
    return _panel(
      key: const Key('study-quiz'),
      children: [
        Text(
          'Questão ${_index + 1} de ${_quiz.length}'
          '${question.concept.isEmpty ? '' : ' · ${question.concept}'}',
          style: const TextStyle(color: MistakeMapDesign.steel),
        ),
        LinearProgressIndicator(value: _index / _quiz.length),
        Text(question.prompt, style: const TextStyle(fontSize: 16)),
        for (var option = 0; option < question.options.length; option++)
          Card(
            margin: EdgeInsets.zero,
            color: chosen == option ? mapBackground : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: chosen == option ? mapTitleBlue : MistakeMapDesign.mist,
              ),
            ),
            child: ListTile(
              key: Key('quiz-option-$option'),
              selected: chosen == option,
              leading: Icon(
                chosen == option
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: mapTitleBlue,
              ),
              title: Text(question.options[option]),
              onTap: _grading
                  ? null
                  : () => setState(() => _answers[question.id] = option),
            ),
          ),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: const TextStyle(color: MistakeMapDesign.bad),
            ),
          ),
        Row(
          spacing: 12,
          children: [
            if (_index > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: _grading ? null : () => setState(() => _index--),
                  child: const Text('Anterior'),
                ),
              ),
            Expanded(
              child: ElevatedButton(
                key: const Key('quiz-next'),
                onPressed: chosen == null || _grading
                    ? null
                    : last
                    ? _grade
                    : () => setState(() => _index++),
                child: Text(
                  last
                      ? (_grading ? 'Corrigindo…' : 'Corrigir quiz')
                      : 'Próxima',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summary(QuizRoundResult result) {
    final missed = result.missedConcepts(_quiz);
    final byId = {for (final q in _quiz) q.id: q};
    final percentage = result.correctPercentage;
    return _panel(
      key: const Key('study-quiz-summary'),
      children: [
        const Text('Resultado do quiz', style: _panelTitle),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _metric(
              'Acertos',
              '${result.correctCount}',
              percentage == null ? null : '${percentage.toStringAsFixed(0)}%',
            ),
            _metric('Erros', '${result.incorrectCount}', null),
            _metric('Questões', '${result.total}', null),
          ],
        ),
        if (missed.isNotEmpty) ...[
          const Text(
            'Revise estes assuntos',
            style: TextStyle(fontWeight: FontWeight.w600, color: mapTitleBlue),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final concept in missed)
                Chip(
                  avatar: const Icon(Icons.bubble_chart_outlined, size: 18),
                  label: Text('${concept.label} (${concept.count})'),
                ),
            ],
          ),
        ] else
          const Text('Você acertou todas. Ótimo trabalho!'),
        const Divider(),
        for (final item in result.results)
          if (byId[item.questionId] case final question?)
            _review(question, item),
        ElevatedButton.icon(
          key: const Key('quiz-restart'),
          onPressed: _restart,
          icon: const Icon(Icons.replay),
          label: const Text('Refazer o quiz'),
        ),
      ],
    );
  }

  Widget _review(QuizQuestion question, QuizQuestionResult item) {
    String option(int? index) =>
        index != null && index >= 0 && index < question.options.length
        ? question.options[index]
        : 'Sem resposta';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Icon(
              item.isCorrect ? Icons.check_circle : Icons.cancel,
              color: item.isCorrect
                  ? MistakeMapDesign.ok
                  : MistakeMapDesign.bad,
              size: 20,
            ),
            Expanded(
              child: Text(
                question.prompt,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: [
              Text('Sua resposta: ${option(item.choice)}'),
              if (!item.isCorrect)
                Text('Resposta correta: ${option(item.correctChoice)}'),
              if (item.explanation.isNotEmpty)
                Text(
                  item.explanation,
                  style: const TextStyle(color: MistakeMapDesign.steel),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../platform/platform_repository.dart';
import '../theme/design_tokens.dart';
import 'class_map_models.dart';
import 'teacher_widgets.dart';

/// Resultado de uma tarefa da turma: quem fez, acerto por questão e erros
/// mais comuns, com cópia em CSV. Acerto individual só de quem autorizou.
class AssignmentResultPage extends StatefulWidget {
  const AssignmentResultPage({
    super.key,
    required this.repository,
    required this.assignmentId,
    required this.title,
  });

  final PlatformRepository repository;
  final String assignmentId;
  final String title;

  @override
  State<AssignmentResultPage> createState() => _AssignmentResultPageState();
}

class _AssignmentResultPageState extends State<AssignmentResultPage> {
  AssignmentResult? _result;
  bool _loading = true;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.repository.execute('assignment_result', {
        'assignment_id': widget.assignmentId,
      });
      if (mounted) setState(() => _result = AssignmentResult.fromJson(data));
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PlatformFailure
              ? error.message
              : 'Não foi possível carregar o resultado. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyCsv(AssignmentResult result) async {
    await Clipboard.setData(ClipboardData(text: result.csv));
    if (mounted) {
      setState(
        () => _notice = 'Resultado copiado. Cole em uma planilha para salvar.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return TeacherPage(
      title: result?.title ?? widget.title,
      subtitle: result == null
          ? 'Resultado da tarefa'
          : '${result.respondents} de ${result.members} alunos responderam · '
                '${result.completed} ${result.completed == 1 ? 'concluiu' : 'concluíram'}',
      error: _error,
      notice: _notice,
      loading: _loading,
      maxWidth: 800,
      children: [
        if (result == null)
          teacherButton('Atualizar', _load)
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              teacherButton(
                'Copiar CSV',
                () => _copyCsv(result),
                primary: true,
              ),
              teacherButton('Atualizar', _load),
            ],
          ),
          const SizedBox(height: 16),
          Text(result.privacy),
          const SizedBox(height: 16),
          _participants(result),
          _questions(result),
          _errors(result),
        ],
      ],
    );
  }

  Widget _participants(AssignmentResult result) => TeacherCard(
    title: 'Quem fez',
    children: [
      if (result.participants.isEmpty)
        const Text('A turma ainda não tem alunos.'),
      for (final p in result.participants)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: assignmentStatusLabels[p.status] ?? 'Não começou',
                      style: TextStyle(
                        color: p.status == 'completed'
                            ? MistakeMapDesign.ok
                            : MistakeMapDesign.content,
                      ),
                    ),
                    TextSpan(
                      text:
                          ' · ${p.answered}/${result.totalQuestions} questões · '
                          '${p.correct == null ? 'acerto não compartilhado' : '${p.correct} ${p.correct == 1 ? 'acerto' : 'acertos'}'}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _questions(AssignmentResult result) => TeacherCard(
    title: 'Acerto por questão',
    children: [
      for (final (index, q) in result.questions.indexed) ...[
        if (index > 0) const SizedBox(height: 16),
        Text(
          'Questão ${q.position} · ${q.theme}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(q.prompt),
        const SizedBox(height: 8),
        if (q.accuracy != null) ...[
          Text(
            '${q.accuracy}% de acerto · ${q.correct} de ${q.responses - (q.pending ?? 0)} '
            '${q.pending != null && q.pending! > 0 ? '· ${q.pending} aguardando correção' : ''}',
          ),
          const SizedBox(height: 4),
          TeacherBar(fraction: q.accuracy! / 100, color: MistakeMapDesign.mint),
        ] else
          Text(
            '${q.responses} ${q.responses == 1 ? 'resposta' : 'respostas'} · '
            'o acerto aparece com 5 respostas ou mais',
          ),
      ],
    ],
  );

  Widget _errors(AssignmentResult result) => TeacherCard(
    title: 'Erros mais comuns',
    children: [
      if (!result.eligible)
        const Text('Aparecem quando 5 alunos ou mais responderem.')
      else if (result.commonErrors.isEmpty)
        const Text('Nenhum erro registrado nesta tarefa.')
      else
        for (final e in result.commonErrors)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${classMapErrorLabel(e.type)}'
              '${e.concept.isEmpty ? '' : ' em ${e.concept}'} · '
              '${e.count} ${e.count == 1 ? 'vez' : 'vezes'}',
            ),
          ),
    ],
  );
}

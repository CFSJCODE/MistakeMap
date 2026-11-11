import 'package:fluent_ui/fluent_ui.dart';

import '../platform/platform_repository.dart';
import '../theme/design_tokens.dart';
import 'class_map_models.dart';
import 'teacher_widgets.dart';

/// Mapa de erros da turma para o professor: os conceitos que mais travam,
/// a grade conceito × tipo de erro e a tendência das últimas 4 semanas.
/// Agregado, sem nomes, e só com 5 alunos ou mais (regra do servidor).
class ClassMapPage extends StatefulWidget {
  const ClassMapPage({
    super.key,
    required this.repository,
    required this.classId,
    required this.classTitle,
  });

  final PlatformRepository repository;
  final String classId;
  final String classTitle;

  @override
  State<ClassMapPage> createState() => _ClassMapPageState();
}

class _ClassMapPageState extends State<ClassMapPage> {
  ClassMap? _map;
  bool _loading = true;
  bool _working = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _message(Object error) => error is PlatformFailure
      ? error.message
      : 'Não foi possível concluir. Tente novamente.';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.repository.execute('class_map', {
        'class_id': widget.classId,
      });
      if (mounted) setState(() => _map = ClassMap.fromJson(data));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _train(ClassMapConcept concept) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
      _notice = null;
    });
    try {
      final data = await widget.repository.execute(
        'create_concept_assignment',
        {'class_id': widget.classId, 'concept': concept.concept},
      );
      final count = data['questions'] is num
          ? (data['questions'] as num).toInt()
          : 0;
      if (mounted) {
        setState(
          () => _notice =
              'Tarefa “Treinar: ${concept.concept}” criada com $count '
              '${count == 1 ? 'questão' : 'questões'} do banco. Ela já aparece '
              'para os alunos da turma.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final map = _map;
    return TeacherPage(
      title: 'Mapa da turma',
      subtitle: '${widget.classTitle} · últimas 4 semanas',
      error: _error,
      notice: _notice,
      loading: _loading,
      children: [
        if (map == null)
          teacherButton('Atualizar', _load)
        else if (!map.eligible)
          TeacherCard(
            title: 'O mapa ainda não pode aparecer',
            children: [
              Text(map.message),
              const SizedBox(height: 8),
              Text(map.privacy),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: teacherButton('Atualizar', _load),
              ),
            ],
          )
        else ...[
          Text(
            '${map.studentsWithData} de ${map.members} alunos estudaram no período. '
            '${map.privacy}',
          ),
          const SizedBox(height: 16),
          _topConcepts(map),
          _grid(map),
          _trend(map),
        ],
      ],
    );
  }

  Widget _topConcepts(ClassMap map) => TeacherCard(
    title: 'Conceitos que mais travam',
    children: [
      if (map.topConcepts.isEmpty)
        const Text('Nenhum erro registrado no período.'),
      for (final (index, c) in map.topConcepts.indexed) ...[
        if (index > 0) const SizedBox(height: 16),
        Text(
          '${index + 1}. ${c.concept}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '${c.subject.isEmpty ? '' : '${c.subject} · '}'
          '${c.students} ${c.students == 1 ? 'aluno' : 'alunos'} · '
          '${c.errors} ${c.errors == 1 ? 'erro' : 'erros'} · '
          'mais comum: ${classMapErrorLabel(c.mainErrorType)} · '
          '${_change(c.lastWeekChange)}',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            teacherButton(
              'Treinar este conceito',
              c.canTrain && !_working ? () => _train(c) : null,
              primary: true,
            ),
            Text(
              c.canTrain
                  ? '${c.questionsAvailable} ${c.questionsAvailable == 1 ? 'questão' : 'questões'} no banco'
                  : 'Ainda sem questões no banco para este conceito',
            ),
          ],
        ),
      ],
    ],
  );

  String _change(int delta) => delta > 0
      ? '+$delta nesta semana'
      : delta < 0
      ? '$delta nesta semana'
      : 'estável nesta semana';

  Widget _grid(ClassMap map) {
    final max = map.maxCell;
    const cellWidth = 128.0;
    Widget cell(String text, {bool header = false, int value = 0}) {
      final strength = max == 0 ? 0.0 : value / max;
      return Container(
        width: cellWidth,
        height: 40,
        alignment: Alignment.center,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: header || value == 0
              ? MistakeMapDesign.well
              : Color.lerp(
                  MistakeMapDesign.hover,
                  MistakeMapDesign.violet,
                  0.15 + strength * 0.6,
                ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: header ? FontWeight.w600 : FontWeight.w400,
            color: MistakeMapDesign.strong,
          ),
        ),
      );
    }

    return TeacherCard(
      title: 'Conceito × tipo de erro',
      children: [
        const Text('Quantos erros a turma teve em cada conceito, por tipo.'),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(width: 184),
                  for (final type in map.errorTypes)
                    cell(classMapErrorLabel(type), header: true),
                ],
              ),
              for (final c in map.grid)
                Row(
                  children: [
                    SizedBox(
                      width: 184,
                      child: Text(
                        c.concept,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final type in map.errorTypes)
                      Semantics(
                        label:
                            '${c.concept}, ${classMapErrorLabel(type)}: ${c.byType[type] ?? 0}',
                        child: cell(
                          '${c.byType[type] ?? 0}',
                          value: c.byType[type] ?? 0,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _trend(ClassMap map) {
    final max = map.trend.fold(0, (m, w) => w.errors > m ? w.errors : m);
    return TeacherCard(
      title: 'Tendência em 4 semanas',
      children: [
        for (final week in map.trend) ...[
          Text(
            '${week.label}: ${week.errors} ${week.errors == 1 ? 'erro' : 'erros'} · '
            '${week.activeStudents} ${week.activeStudents == 1 ? 'aluno ativo' : 'alunos ativos'}',
          ),
          const SizedBox(height: 4),
          TeacherBar(fraction: max == 0 ? 0 : week.errors / max),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

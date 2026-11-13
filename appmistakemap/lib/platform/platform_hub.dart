import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

import '../theme/motion.dart';
import '../about/external_profile.dart' show openLearningLink;
import '../sync/conexao.dart' show novoUuid;
import '../teacher/assignment_result_page.dart';
import '../teacher/class_map_page.dart';
import '../theme/control_styles.dart';
import '../theme/design_tokens.dart';
import 'platform_repository.dart';
import 'platform_session.dart';
import 'platform_forms.dart';

export 'platform_forms.dart';

const _difficultyLabels = {
  'facil': 'Fácil',
  'media': 'Média',
  'dificil': 'Difícil',
};
const _statusLabels = {
  'active': 'Em andamento',
  'completed': 'Concluída',
  'pending': 'Pendente',
  'processing': 'Em processamento',
  'cancelled': 'Cancelada',
  'draft': 'Rascunho',
  'pending_review': 'Aguardando revisão',
  'rejected': 'Correções solicitadas',
  'published': 'Publicado',
};

class PlatformHubPage extends StatefulWidget {
  const PlatformHubPage({
    super.key,
    required this.userId,
    this.repository,
    this.isAdmin = false,
    this.onOpenQuestionAssignment,
  });
  final String userId;
  final PlatformRepository? repository;
  final bool isAdmin;

  /// Abre uma tarefa com questões do banco (criada pelo mapa da turma).
  /// Devolve uma mensagem de erro para mostrar, ou nulo.
  final Future<String?> Function(
    BuildContext context,
    String assignmentId,
    List<String> questionIds,
  )?
  onOpenQuestionAssignment;

  @override
  State<PlatformHubPage> createState() => _PlatformHubPageState();
}

class _PlatformHubPageState extends State<PlatformHubPage> {
  late final PlatformRepository _repository =
      widget.repository ?? SupabasePlatformRepository(Supabase.instance.client);
  final _search = TextEditingController();
  PlatformData _overview = {};
  List<PlatformData> _catalog = [];
  List<PlatformData> _drafts = [];
  bool _canPublish = false;
  String _section = 'Biblioteca';
  String? _error;
  String? _notice;
  bool _loading = true;
  bool _working = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repository.execute('overview'),
        _repository.execute('catalog', {'query': _search.text.trim()}),
      ]);
      PlatformData content = {};
      if (widget.isAdmin ||
          platformMap(results[0]['entitlements'])['teacher_enabled'] == true) {
        content = await _repository.execute('content_drafts');
      }
      if (!mounted) return;
      setState(() {
        _overview = results[0];
        _catalog = platformRows(results[1]['exercises']);
        _drafts = platformRows(content['drafts']);
        _canPublish = content['can_publish'] == true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object error) => error is PlatformFailure
      ? error.message
      : 'Não foi possível concluir. Tente novamente.';

  Future<PlatformData?> _run(String action, PlatformData input) async {
    if (_working) return null;
    setState(() {
      _working = true;
      _error = null;
      _notice = null;
    });
    try {
      return await _repository.execute(action, input);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
      return null;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _edit(
    String title,
    List<PlatformField> fields,
    String action,
    PlatformData Function(Map<String, String>) values,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => PlatformFormDialog(
        title: title,
        fields: fields,
        requireRights: const {
          'save_material',
          'save_content_draft',
        }.contains(action),
        confirmations: action == 'publish_content_draft'
            ? const {
                'answer_verified':
                    'Conferi o gabarito e a resolução deste exercício.',
                'technology_confirmed': 'Conferi a temática de tecnologia e a adequação ao nível curricular.',
              }
            : const {},
        onSave: (data) async {
          final input = values(data);
          if (action == 'publish_content_draft') {
            input['answer_verified'] = data['answer_verified'] == 'true';
            input['technology_confirmed'] =
                data['technology_confirmed'] == 'true';
          }
          await _repository.execute(action, input);
        },
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _session(PlatformData session) async {
    await Navigator.of(context).push<void>(
      MistakeMapPageRoute(
        context: context,
        builder: (_) =>
            PlatformSessionPage(repository: _repository, session: session),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _start({
    PlatformData? exercise,
    String mode = 'practice',
    String? goalId,
  }) async {
    if (_starting) return;
    _starting = true;
    try {
      final payload = <String, dynamic>{
        'mode': mode,
        'count': 5,
        if (exercise?['subject'] != null) 'subject': exercise!['subject'],
        if (exercise?['theme'] != null) 'theme': exercise!['theme'],
        'goal_id': ?goalId,
      };
      final preferences = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 2),
      );
      final signature = sha256
          .convert(utf8.encode(jsonEncode(payload)))
          .toString();
      final key = 'mistakemap.platform.request.${widget.userId}.$signature';
      final requestId = preferences.getString(key) ?? novoUuid();
      await preferences.setString(key, requestId);
      final result = await _run('start_session', {
        'request_id': requestId,
        ...payload,
      });
      if (result != null && mounted) {
        await preferences.remove(key);
        await _session(platformMap(result['session']));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      _starting = false;
    }
  }

  Widget _button(String text, VoidCallback action, {bool primary = false}) {
    final style = MistakeMapControls.button(
      background: primary ? MistakeMapDesign.aqua : null,
      foreground: primary ? MistakeMapDesign.abyss : null,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: MistakeMapButton(
        style: style,
        onPressed: _working ? null : action,
        child: Text(text),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: MistakeMapDesign.surface,
      border: Border.all(color: MistakeMapDesign.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );

  List<Widget> _library({bool trails = false}) {
    if (trails) {
      final themes = <String, PlatformData>{};
      for (final item in _catalog) {
        themes['${item['subject']}/${item['theme']}'] = item;
      }
      return [
        const Text(
          'Percursos de prática com questões revisadas, organizados por matéria e habilidade. Ao terminar, confira o resultado e volte para revisar.',
        ),
        const SizedBox(height: 24),
        for (final item in themes.values)
          _card('${item['subject']} · ${item['theme']}', [
            Text('${item['topic']} · exercícios com temática de tecnologia'),
            const SizedBox(height: 16),
            _button(
              'Começar percurso',
              () => _start(exercise: item),
              primary: true,
            ),
          ]),
        if (themes.isEmpty)
          const Text('Nenhum percurso encontrado para esta busca.'),
      ];
    }
    return [
      InfoLabel(
        label: 'Buscar por matéria, assunto ou tema',
        child: TextBox(
          controller: _search,
          placeholder: 'Ex.: Física, Newton, sensores',
          prefix: const Padding(
            padding: EdgeInsetsDirectional.only(start: 10),
            child: Icon(WindowsIcons.search, size: 16),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
        ),
      ),
      const SizedBox(height: 8),
      _button('Buscar no catálogo', _load),
      const SizedBox(height: 24),
      if (_catalog.isEmpty)
        const Text('Nenhum exercício encontrado. Experimente outro termo.'),
      for (final item in _catalog)
        _card('${item['subject']} · ${item['theme']}', [
          Text(
            '${item['topic']} · ${_difficultyLabels[item['difficulty']] ?? 'Dificuldade não informada'} · conteúdo revisado',
          ),
          const SizedBox(height: 16),
          SelectableText('${item['prompt_text']}'),
          const SizedBox(height: 16),
          _button(
            'Praticar este tema',
            () => _start(exercise: item),
            primary: true,
          ),
          const SizedBox(height: 8),
          _button(
            'Anotar regra deste exercício',
            () => _edit(
              'O que você aprendeu?',
              [
                PlatformField('title', 'Título', initial: '${item['theme']}'),
                const PlatformField(
                  'body',
                  'Regra com suas palavras',
                  multiline: true,
                ),
              ],
              'save_note',
              (v) => {
                ...v,
                'concept': item['theme'],
                'catalog_exercise_id': item['id'],
              },
            ),
          ),
        ]),
    ];
  }

  Future<void> _editGoal(PlatformData goal) => _edit(
    'Editar objetivo',
    [
      PlatformField('title', 'Objetivo', initial: '${goal['title']}'),
      PlatformField(
        'exam_date',
        'Data da prova (AAAA-MM-DD)',
        required: false,
        initial: '${goal['exam_date'] ?? ''}',
      ),
      PlatformField(
        'minutes',
        'Minutos por dia',
        initial: '${goal['minutes_per_day']}',
      ),
      PlatformField(
        'subjects',
        'Assuntos separados por vírgula',
        initial: (goal['subjects'] as List? ?? []).join(', '),
      ),
    ],
    'save_goal',
    (v) => {
      'id': goal['id'],
      'title': v['title'],
      'exam_date': v['exam_date']!.isEmpty ? null : v['exam_date'],
      'minutes_per_day': int.tryParse(v['minutes']!) ?? 0,
      'subjects': v['subjects']!
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    },
  );

  List<Widget> _plans() => [
    _button(
      'Criar plano para prova',
      () => _edit(
        'Seu próximo objetivo',
        const [
          PlatformField('title', 'Objetivo', hint: 'Ex.: Prova de Circuitos'),
          PlatformField(
            'exam_date',
            'Data da prova (AAAA-MM-DD)',
            required: false,
          ),
          PlatformField('minutes', 'Minutos por dia', initial: '15'),
          PlatformField('subjects', 'Assuntos separados por vírgula'),
        ],
        'save_goal',
        (v) => {
          'title': v['title'],
          'exam_date': v['exam_date']!.isEmpty ? null : v['exam_date'],
          'minutes_per_day': int.tryParse(v['minutes']!) ?? 0,
          'subjects': v['subjects']!
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
        },
      ),
      primary: true,
    ),
    const SizedBox(height: 24),
    if (platformRows(_overview['goals']).isEmpty)
      const Text('Defina uma prova ou objetivo para organizar sua preparação.'),
    for (final goal in platformRows(_overview['goals']))
      _card('${goal['title']}', [
        Text(
          'Data: ${goal['exam_date'] ?? 'sem prazo'} · ${goal['minutes_per_day']} min/dia',
        ),
        const SizedBox(height: 8),
        Text('Assuntos: ${(goal['subjects'] as List? ?? []).join(', ')}'),
        if (goal['refresh_recommended'] == true)
          Text(
            '${goal['refresh_notice'] ?? 'Atualize o plano para os próximos dias.'}',
          ),
        if (goal['weekly_plan'] != null) ...[
          const SizedBox(height: 16),
          for (final day in platformRows(goal['weekly_plan']))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${day['date']} · ${day['minutes']} min\n${day['subject']} · ${day['theme']}\n${day['activity']}',
              ),
            ),
        ],
        const SizedBox(height: 16),
        _button('Praticar agora', () {
          final days = platformRows(goal['weekly_plan']);
          final subjects = goal['subjects'] as List? ?? [];
          final focus = days.isNotEmpty
              ? days.first
              : <String, dynamic>{
                  if (subjects.isNotEmpty) 'subject': subjects.first,
                };
          _start(
            exercise: focus.isEmpty ? null : focus,
            goalId: '${goal['id']}',
          );
        }),
        const SizedBox(height: 8),
        _button('Reorganizar semana', () async {
          final result = await _run('refresh_goal', {'id': goal['id']});
          if (result != null && mounted) await _load();
        }),
        const SizedBox(height: 8),
        _button('Editar plano', () => _editGoal(goal)),
        const SizedBox(height: 8),
        _button('Excluir plano', () => _deleteRecord('delete_goal', goal)),
      ]),
  ];

  List<Widget> _sessions() => [
    const Text(
      'No modo prova, as pistas ficam desativadas. A correção aparece ao finalizar; você pode sair e continuar depois.',
    ),
    const SizedBox(height: 16),
    _button(
      'Novo simulado · 5 questões',
      () => _start(mode: 'exam'),
      primary: true,
    ),
    const SizedBox(height: 24),
    for (final session in platformRows(_overview['sessions']))
      _card('${session['title']}', [
        Text(
          '${session['mode'] == 'exam' ? 'Simulado' : 'Prática'} · ${_statusLabels[session['status']] ?? 'Salva'}',
        ),
        if (session['finished_at'] != null)
          Text(
            '${session['correct_count'] ?? 0} de ${session['total'] ?? 0} respostas equivalentes ao gabarito${session['assisted'] == true ? ' · com pistas' : ''}',
          ),
        const SizedBox(height: 16),
        _button(
          session['finished_at'] == null
              ? 'Continuar sessão'
              : 'Ver devolutiva',
          () async {
            final data = await _run('get_session', {
              'session_id': session['id'],
            });
            if (data != null && mounted) {
              await _session(platformMap(data['session']));
            }
          },
        ),
      ]),
    if (platformRows(_overview['sessions']).isEmpty)
      const Text('Suas sessões salvas aparecerão aqui.'),
  ];

  List<Widget> _materials() => [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _button(
          'Adicionar material',
          () => _edit(
            'Material de referência',
            const [
              PlatformField('title', 'Título'),
              PlatformField('url', 'Link HTTPS do PDF ou material'),
              PlatformField('page', 'Página de referência', required: false),
              PlatformField(
                'notes',
                'Anotações',
                multiline: true,
                required: false,
              ),
            ],
            'save_material',
            (v) => {
              'title': v['title'],
              'url': v['url'],
              'page_number': int.tryParse(v['page']!),
              'notes': v['notes'],
              'rights_confirmed': v['rights_confirmed'] == 'true',
            },
          ),
        ),
        _button(
          'Conectar uma anotação',
          () => _edit(
            'O que você aprendeu?',
            const [
              PlatformField('title', 'Título'),
              PlatformField('body', 'Regra com suas palavras', multiline: true),
              PlatformField(
                'concept',
                'Conceito ou habilidade',
                required: false,
              ),
            ],
            'save_note',
            (v) => {...v},
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    const Text(
      'Guarde referências e páginas de consulta. O link não importa nem analisa automaticamente o conteúdo do arquivo.',
    ),
    const SizedBox(height: 24),
    for (final item in platformRows(_overview['materials']))
      _card('${item['title']}', [
        Text('${item['notes'] ?? ''}'),
        if (item['page_number'] != null) Text('Página ${item['page_number']}'),
        const SizedBox(height: 16),
        _button('Abrir referência', () async {
          final uri = Uri.tryParse('${item['url']}');
          if (uri == null ||
              uri.scheme != 'https' ||
              !await openLearningLink(uri)) {
            if (mounted) {
              setState(() => _error = 'Não foi possível abrir o material.');
            }
          }
        }),
        const SizedBox(height: 8),
        _button(
          'Excluir material',
          () => _deleteRecord('delete_material', item),
        ),
      ]),
    for (final note in platformRows(_overview['notes']))
      _card('${note['title']}', [
        Text('${note['concept'] ?? 'Anotação de estudo'}'),
        const SizedBox(height: 8),
        SelectableText('${note['body']}'),
        const SizedBox(height: 16),
        _button('Excluir anotação', () => _deleteRecord('delete_note', note)),
      ]),
  ];

  List<Widget> _classes() {
    final entitlement = platformMap(_overview['entitlements']);
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _button(
            'Entrar em uma turma',
            () => _edit(
              'Convite da turma',
              const [PlatformField('code', 'Código fornecido pelo professor')],
              'join_class',
              (v) => {...v},
            ),
          ),
          if (entitlement['teacher_enabled'] == true || widget.isAdmin)
            _button(
              'Criar turma',
              () => _edit(
                'Nova turma',
                const [PlatformField('title', 'Nome da turma')],
                'create_class',
                (v) => {...v},
              ),
            ),
          if (widget.isAdmin)
            _button(
              'Habilitar professor',
              () => _edit(
                'Habilitar professor',
                const [
                  PlatformField('user_id', 'Identificador da conta (UUID)'),
                ],
                'grant_teacher',
                (v) => {...v},
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'Você controla o compartilhamento em cada turma. Entrar não libera automaticamente respostas ou anotações.',
      ),
      const SizedBox(height: 24),
      for (final item in platformRows(_overview['classes']))
        _card('${item['title']}', [
          if (item['code'] != null)
            SelectableText('Código de convite: ${item['code']}'),
          if (item['is_teacher'] == true) ...[
            const SizedBox(height: 16),
            _button(
              'Mapa da turma',
              () => _push(
                ClassMapPage(
                  repository: _repository,
                  classId: '${item['id']}',
                  classTitle: '${item['title']}',
                ),
              ),
              primary: true,
            ),
            const SizedBox(height: 8),
            _button('Atribuir lista do catálogo', () => _assign(item)),
            const SizedBox(height: 8),
            _button(
              'Ver acompanhamento autorizado',
              () => _classProgress(item),
            ),
          ] else ...[
            for (final setting in const {
              'share_progress': 'Compartilhar progresso',
              'share_answers': 'Compartilhar respostas',
              'share_notes': 'Compartilhar anotações',
            }.entries)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: PlatformCheck(
                  content: Text(setting.value),
                  checked: item[setting.key] == true,
                  onChanged: _working
                      ? null
                      : (value) async {
                          final result = await _run('set_sharing', {
                            'class_id': item['id'],
                            'share_progress': item['share_progress'] == true,
                            'share_answers': item['share_answers'] == true,
                            'share_notes': item['share_notes'] == true,
                            setting.key: value == true,
                          });
                          if (result != null && mounted) await _load();
                        },
                ),
              ),
            const SizedBox(height: 16),
            _button('Sair da turma', () async {
              final result = await _run('leave_class', {
                'class_id': item['id'],
              });
              if (result != null && mounted) await _load();
            }),
          ],
        ]),
      for (final assignment in platformRows(_overview['assignments']))
        _assignmentCard(assignment),
      if (platformRows(_overview['classes']).isEmpty)
        const Text('Entre com um convite para estudar com sua turma.'),
      for (final feedback in platformRows(_overview['feedback']))
        _card('Orientação do professor · ${feedback['class_title']}', [
          Text('${feedback['session_title']}'),
          const SizedBox(height: 16),
          SelectableText('${feedback['body']}'),
        ]),
    ];
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(
      context,
    ).push<void>(MistakeMapPageRoute(context: context, builder: (_) => page));
    if (mounted) await _load();
  }

  Widget _assignmentCard(PlatformData assignment) {
    final questionIds = [
      for (final id
          in (assignment['question_ids'] is List
              ? assignment['question_ids'] as List
              : const []))
        '$id',
    ];
    final teaches = platformRows(
      _overview['classes'],
    ).any((c) => c['id'] == assignment['class_id'] && c['is_teacher'] == true);
    return _card('${assignment['title']}', [
      Text('Prazo: ${assignment['due_at'] ?? 'sem prazo'}'),
      if (questionIds.isNotEmpty)
        Text(
          '${questionIds.length} ${questionIds.length == 1 ? 'questão' : 'questões'} do banco',
        ),
      const SizedBox(height: 16),
      if (teaches && questionIds.isNotEmpty)
        _button(
          'Ver resultado',
          () => _push(
            AssignmentResultPage(
              repository: _repository,
              assignmentId: '${assignment['id']}',
              title: '${assignment['title']}',
            ),
          ),
        )
      else if (questionIds.isNotEmpty)
        _button('Responder tarefa', () async {
          final open = widget.onOpenQuestionAssignment;
          if (open == null) {
            setState(
              () => _error = 'Abra esta tarefa pela aba Exercícios do app.',
            );
            return;
          }
          final failure = await open(
            context,
            '${assignment['id']}',
            questionIds,
          );
          if (!mounted) return;
          if (failure != null) {
            setState(() => _error = failure);
          } else {
            await _load();
          }
        })
      else
        _button('Responder lista', () async {
          final result = await _run('start_session', {
            'request_id': novoUuid(),
            'mode': 'practice',
            'count': 5,
            'assignment_id': assignment['id'],
          });
          if (result != null && mounted) {
            await _session(platformMap(result['session']));
          }
        }),
    ]);
  }

  Future<void> _classProgress(PlatformData item) async {
    final result = await _run('class_progress', {'class_id': item['id']});
    if (result == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ContentDialog(
        title: Text('Acompanhamento · ${item['title']}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${result['scope'] ?? 'Dados compartilhados pelos participantes.'}',
              ),
              const SizedBox(height: 16),
              if (platformRows(result['students']).isEmpty)
                const Text('Ainda não há participantes.'),
              for (final (index, student) in platformRows(
                result['students'],
              ).indexed) ...[
                Text(
                  'Participante ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (student['share_progress'] == true)
                  Text(
                    '${platformMap(student['progress'])['correct'] ?? 0} respostas equivalentes em ${platformMap(student['progress'])['attempts'] ?? 0} questões',
                  )
                else
                  const Text('Progresso não compartilhado'),
                for (final answer in platformRows(student['answers'])) ...[
                  Text('${answer['title']}'),
                  for (final result in platformRows(answer['results']))
                    Text('Resposta: ${result['answer']}'),
                  for (final feedback in platformRows(answer['feedback']))
                    Text('Seu parecer: ${feedback['body']}'),
                  const SizedBox(height: 8),
                  _button(
                    'Enviar feedback',
                    () => _edit(
                      'Orientar o estudante',
                      const [
                        PlatformField(
                          'body',
                          'Seu comentário sobre a resolução',
                          multiline: true,
                        ),
                      ],
                      'save_feedback',
                      (v) => {'session_id': answer['id'], ...v},
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                for (final note in platformRows(student['notes']))
                  Text('${note['title']}: ${note['body']}'),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _assign(PlatformData item) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => PlatformAssignmentDialog(
        repository: _repository,
        classId: '${item['id']}',
        catalog: _catalog,
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _deleteRecord(String action, PlatformData item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('Excluir este registro?'),
        content: Text('“${item['title']}” será removido da sua conta.'),
        actions: [
          MistakeMapButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          MistakeMapFilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await _run(action, {'id': item['id']});
    if (result != null && mounted) await _load();
  }

  Future<void> _editDraft(PlatformData draft) => _edit(
    'Editar exercício',
    [
      for (final field in const <String, String>{
        'subject': 'Matéria',
        'topic': 'Assunto',
        'theme': 'Tema ou habilidade',
        'position': 'Posição no conjunto (1 a 5)',
        'difficulty': 'Dificuldade: facil, media ou dificil',
        'error_category': 'Categoria do erro',
        'technology_context': 'Dispositivo ou sistema protagonista',
        'prompt_text': 'Enunciado',
        'correct_answer': 'Resposta de referência',
        'explanation': 'Resolução comentada',
      }.entries)
        PlatformField(
          field.key,
          field.value,
          initial: '${draft[field.key] ?? ''}',
          multiline: const {'prompt_text', 'explanation'}.contains(field.key),
        ),
    ],
    'save_content_draft',
    (v) => {
      ...v,
      'id': draft['id'],
      'position': int.tryParse(v['position']!) ?? 0,
      'rights_confirmed': v['rights_confirmed'] == 'true',
    },
  );

  List<Widget> _account() {
    final plan = platformMap(_overview['entitlements']);
    final progress = platformMap(_overview['progress']);
    return [
      _card('Seu plano e consumo', [
        Text('Plano: ${plan['plan_label'] ?? plan['plan'] ?? 'gratuito'}'),
        const SizedBox(height: 8),
        Text(
          'Sessões hoje: ${plan['sessions_used_today'] ?? 0} de ${plan['sessions_per_day'] ?? '—'}',
        ),
        const SizedBox(height: 8),
        const Text(
          'A cobrança está desativada. Seus conteúdos continuam acessíveis; o limite de sessões protege a capacidade do serviço.',
        ),
      ]),
      _card('Progresso com evidências', [
        Text(
          '${progress['correct'] ?? 0} respostas equivalentes ao gabarito em ${progress['attempts'] ?? 0} questões · últimos ${progress['period_days'] ?? 30} dias',
        ),
        const SizedBox(height: 8),
        Text(
          '${progress['label'] ?? 'Sem evidências suficientes para estimar evolução.'}',
        ),
        const SizedBox(height: 16),
        _button('Ver meu resumo semanal', _week),
        const SizedBox(height: 8),
        _button('Copiar relatório CSV', () async {
          final report = await _run('report_csv', {});
          if (report != null) {
            await Clipboard.setData(
              ClipboardData(text: '${report['csv'] ?? ''}'),
            );
            if (mounted) {
              setState(
                () => _notice =
                    'Relatório copiado. Cole em uma planilha para salvar.',
              );
            }
          }
        }),
      ]),
      _card('Seus dados', [
        const Text(
          'Exporte seus registros ou solicite a exclusão completa da conta. Uma solicitação de exclusão fica pendente até ser processada; não significa que seus dados já foram apagados.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _button('Exportar meus dados', _export),
            _button(
              'Solicitar exclusão da conta',
              () => _edit(
                'Solicitar exclusão',
                const [
                  PlatformField('confirmation', 'Digite EXCLUIR MINHA CONTA'),
                ],
                'request_deletion',
                (v) => {...v},
              ),
            ),
          ],
        ),
        for (final request in platformRows(_overview['privacy_requests'])) ...[
          const SizedBox(height: 16),
          Text(
            'Solicitação: ${_statusLabels[request['status']] ?? 'Registrada'} · ${request['created_at']}',
          ),
          if (request['status'] == 'pending')
            _button('Cancelar solicitação', () async {
              final result = await _run('cancel_deletion', {
                'id': request['id'],
              });
              if (result != null && mounted) await _load();
            }),
        ],
      ]),
    ];
  }

  Future<void> _export() async {
    final data = await _run('export_data', {});
    if (data == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          PlatformExportDialog(repository: _repository, initial: data),
    );
  }

  Future<void> _week() async {
    final data = await _run('weekly_summary', {});
    if (data == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          PlatformWeekDialog(repository: _repository, initial: data),
    );
  }

  // Mesmo cabeçalho das outras telas internas (Explorar e aprender, Sobre):
  // seta de voltar à esquerda e o título ao lado, na mesma linha.
  Widget _header() => Row(
    children: [
      Tooltip(
        message: 'Voltar',
        child: SizedBox.square(
          dimension: 40,
          child: MistakeMapIconButton(
            style: MistakeMapControls.button(
              padding: const EdgeInsets.all(11),
              foreground: MistakeMapDesign.primary,
            ),
            icon: const Icon(WindowsIcons.back, size: 18),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Text(
          'Seu espaço de estudos',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: MistakeMapDesign.primary,
          ),
        ),
      ),
    ],
  );

  List<Widget> _content() => [
    const Text(
      'Prepare exercícios com temática de tecnologia. Todo material passa por revisão administrativa antes de entrar no catálogo dos estudantes.',
    ),
    const SizedBox(height: 16),
    _button(
      'Escrever exercício',
      () => _edit(
        'Novo exercício de tecnologia',
        const [
          PlatformField('subject', 'Matéria'),
          PlatformField('topic', 'Assunto'),
          PlatformField('theme', 'Tema ou habilidade'),
          PlatformField(
            'position',
            'Posição no conjunto (1 a 5)',
            initial: '1',
          ),
          PlatformField(
            'difficulty',
            'Dificuldade: facil, media ou dificil',
            initial: 'facil',
          ),
          PlatformField(
            'error_category',
            'Categoria: calculo, conceito, sinal, interpretacao, procedimento, unidade ou outro',
            initial: 'conceito',
          ),
          PlatformField(
            'technology_context',
            'Dispositivo ou sistema protagonista',
          ),
          PlatformField('prompt_text', 'Enunciado', multiline: true),
          PlatformField('correct_answer', 'Resposta de referência'),
          PlatformField('explanation', 'Resolução comentada', multiline: true),
        ],
        'save_content_draft',
        (v) => {
          ...v,
          'position': int.tryParse(v['position']!) ?? 0,
          'rights_confirmed': v['rights_confirmed'] == 'true',
        },
      ),
      primary: true,
    ),
    const SizedBox(height: 24),
    for (final draft in _drafts)
      _card('${draft['subject']} · ${draft['theme']}', [
        Text('Situação: ${_statusLabels[draft['status']] ?? 'Registrada'}'),
        const SizedBox(height: 16),
        SelectableText('${draft['prompt_text']}'),
        const SizedBox(height: 8),
        Text('Referência de revisão: ${draft['correct_answer']}'),
        if ((draft['review_note'] as String? ?? '').isNotEmpty)
          Text('Parecer: ${draft['review_note']}'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (draft['status'] != 'published')
              _button('Editar rascunho', () => _editDraft(draft)),
            if (draft['status'] == 'draft' || draft['status'] == 'rejected')
              _button('Enviar para revisão', () async {
                final result = await _run('submit_content_draft', {
                  'id': draft['id'],
                });
                if (result != null && mounted) await _load();
              }),
            if (_canPublish && draft['status'] == 'pending_review') ...[
              _button(
                'Aprovar e publicar',
                () => _edit(
                  'Revisão do exercício',
                  const [PlatformField('review_note', 'Parecer da revisão')],
                  'publish_content_draft',
                  (v) => {'id': draft['id'], ...v},
                ),
              ),
              _button(
                'Solicitar correção',
                () => _edit(
                  'Orientação ao autor',
                  const [
                    PlatformField(
                      'review_note',
                      'O que precisa ser corrigido?',
                    ),
                  ],
                  'reject_content_draft',
                  (v) => {'id': draft['id'], ...v},
                ),
              ),
            ],
          ],
        ),
      ]),
    if (_drafts.isEmpty)
      const Text('Seus exercícios em preparação aparecerão aqui.'),
  ];

  @override
  Widget build(BuildContext context) => NavigationView(
    content: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 4),
            child: _header(),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final section in [
                          'Biblioteca',
                          'Trilhas',
                          'Plano',
                          'Simulados',
                          'Materiais',
                          'Turmas',
                          'Conta',
                          if (widget.isAdmin ||
                              platformMap(
                                    _overview['entitlements'],
                                  )['teacher_enabled'] ==
                                  true)
                            'Conteúdo',
                        ])
                          _button(
                            section,
                            () => setState(() => _section = section),
                            primary: section == _section,
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      InfoBar(
                        title: const Text('Vamos tentar de novo'),
                        content: Text(_error!),
                        severity: InfoBarSeverity.warning,
                      ),
                      const SizedBox(height: 16),
                      _button('Atualizar', _load),
                    ],
                    if (_notice != null) ...[
                      InfoBar(
                        title: const Text('Concluído'),
                        content: Text(_notice!),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_loading)
                      const Center(child: ProgressRing())
                    else
                      ...switch (_section) {
                        'Biblioteca' => _library(),
                        'Trilhas' => _library(trails: true),
                        'Plano' => _plans(),
                        'Simulados' => _sessions(),
                        'Materiais' => _materials(),
                        'Turmas' => _classes(),
                        'Conteúdo' => _content(),
                        _ => _account(),
                      },
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

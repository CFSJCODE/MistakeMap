part of 'main.dart';

/// Catálogo compartilhado; o conteúdo e as permissões vêm do servidor.
class TelaAprender extends StatefulWidget {
  const TelaAprender({super.key, this.isAdmin = false});
  final bool isAdmin;

  @override
  State<TelaAprender> createState() => _TelaAprenderState();
}

class _TelaAprenderState extends State<TelaAprender> {
  String _stage = 'fundamental';
  int _grade = 7;
  late Future<List<List<Map<String, dynamic>>>> _data = _load();

  Future<void> _editPost([Map<String, dynamic>? post]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PostEditor(post: post),
    );
    if (result == null || !mounted) return;
    try {
      if (post == null) {
        await _db.from('knowledge_posts').insert(result);
      } else {
        await _db.from('knowledge_posts').update(result).eq('id', post['id']);
      }
      if (mounted) setState(() => _data = _load());
    } catch (_) {
      if (mounted) {
        _avisar(context, 'Não foi possível salvar a publicação.', erro: true);
      }
    }
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    final confirmed = await _confirmar(
      context,
      titulo: 'Excluir publicação',
      mensagem: 'Deseja excluir esta publicação?',
      confirmar: 'Excluir',
    );
    if (!confirmed || !mounted) return;
    try {
      await _db.from('knowledge_posts').delete().eq('id', post['id']);
      if (mounted) setState(() => _data = _load());
    } catch (_) {
      if (mounted) {
        _avisar(context, 'Não foi possível excluir a publicação.', erro: true);
      }
    }
  }

  Future<List<List<Map<String, dynamic>>>> _load() async {
    final subjects = await _db
        .from('learning_subjects')
        .select('stage, grade, course, name')
        .order('name');
    final posts = await _db
        .from('knowledge_posts')
        .select('id, title, body, category, link_url')
        .order('created_at', ascending: false)
        .limit(30);
    return [
      subjects.map((row) => Map<String, dynamic>.from(row)).toList(),
      posts.map((row) => Map<String, dynamic>.from(row)).toList(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return _PaginaVidro(
      titulo: 'Explorar e aprender',
      voltar: true,
      corpo: FutureBuilder<List<List<Map<String, dynamic>>>>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: ProgressRing());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Não foi possível carregar os conteúdos.'),
                  const SizedBox(height: 16),
                  Button(
                    onPressed: () => setState(() => _data = _load()),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }
          final subjects = snapshot.data![0].where(
            (subject) =>
                subject['stage'] == _stage &&
                ((_stage != 'fundamental' && _stage != 'medio') ||
                    subject['grade'] == _grade),
          );
          final posts = snapshot.data![1];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: _paddingCorpo(context),
                children: [
                  Text(
                    'Sua jornada de aprendizado',
                    style: context.tipo.subtitle?.copyWith(color: titleBlue),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Explore a educação básica, a graduação e o estudo independente com uma perspectiva de tecnologia.',
                  ),
                  const SizedBox(height: 16),
                  ComboBox<String>(
                    value: _stage,
                    isExpanded: true,
                    items: const [
                      ComboBoxItem(
                        value: 'fundamental',
                        child: Text('Ensino Fundamental'),
                      ),
                      ComboBoxItem(value: 'medio', child: Text('Ensino Médio')),
                      ComboBoxItem(
                        value: 'superior',
                        child: Text('Engenharia de Computação'),
                      ),
                      ComboBoxItem(
                        value: 'autodidata',
                        child: Text('Estudo independente'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _stage = value;
                          _grade = value == 'fundamental' ? 7 : 1;
                        });
                      }
                    },
                  ),
                  if (_stage == 'fundamental' || _stage == 'medio') ...[
                    const SizedBox(height: 8),
                    ComboBox<int>(
                      value: _grade,
                      isExpanded: true,
                      items: [
                        for (final grade
                            in _stage == 'fundamental' ? [7, 8, 9] : [1, 2, 3])
                          ComboBoxItem(
                            value: grade,
                            child: Text('$gradeº ano'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _grade = value);
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (subjects.isEmpty)
                    const Text('Nenhuma matéria disponível nesta etapa.'),
                  const Text(
                    'Os exercícios para estas matérias estão em preparação.',
                  ),
                  const SizedBox(height: 8),
                  for (final subject in subjects)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PainelVidro(
                        child: Text(
                          subject['grade'] == null
                              ? '${subject['name']}'
                              : '${subject['grade']}º ano · ${subject['name']}',
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Conhecimentos e projetos',
                    style: context.tipo.subtitle?.copyWith(color: titleBlue),
                  ),
                  const SizedBox(height: 8),
                  if (widget.isAdmin) ...[
                    Button(
                      onPressed: () => _editPost(),
                      child: const Text('Nova publicação'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (posts.isEmpty)
                    const Text('Ainda não há publicações disponíveis.'),
                  for (final post in posts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PainelVidro(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post['title'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(post['body'] as String),
                            if ((post['link_url'] as String?)?.isNotEmpty ??
                                false) ...[
                              const SizedBox(height: 8),
                              Button(
                                onPressed: () async {
                                  final uri = Uri.tryParse(
                                    post['link_url'] as String,
                                  );
                                  if (uri == null ||
                                      uri.scheme != 'https' ||
                                      uri.host.isEmpty ||
                                      !await openLearningLink(uri)) {
                                    if (context.mounted) {
                                      _avisar(
                                        context,
                                        'Não foi possível abrir o link.',
                                        erro: true,
                                      );
                                    }
                                  }
                                },
                                child: const Text('Abrir link'),
                              ),
                            ],
                            if (widget.isAdmin) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  Button(
                                    onPressed: () => _editPost(post),
                                    child: const Text('Editar'),
                                  ),
                                  Button(
                                    onPressed: () => _deletePost(post),
                                    child: const Text('Excluir'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PostEditor extends StatefulWidget {
  const _PostEditor({this.post});
  final Map<String, dynamic>? post;

  @override
  State<_PostEditor> createState() => _PostEditorState();
}

class _PostEditorState extends State<_PostEditor> {
  late final _title = TextEditingController(
    text: widget.post?['title'] as String? ?? '',
  );
  late final _body = TextEditingController(
    text: widget.post?['body'] as String? ?? '',
  );
  late final _link = TextEditingController(
    text: widget.post?['link_url'] as String? ?? '',
  );
  late String _category = widget.post?['category'] as String? ?? 'dicas';
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _link.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    final body = _body.text.trim();
    final link = _link.text.trim();
    final uri = Uri.tryParse(link);
    if (title.isEmpty ||
        title.length > 140 ||
        body.isEmpty ||
        body.length > 20000 ||
        (link.isNotEmpty &&
            (uri == null || uri.scheme != 'https' || uri.host.isEmpty))) {
      setState(
        () => _error = 'Informe título e conteúdo válidos. O link, se informado, deve começar com https://.',
      );
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'title': title,
      'body': body,
      'category': _category,
      'link_url': link.isEmpty ? null : link,
    });
  }

  @override
  Widget build(BuildContext context) => ContentDialog(
    title: Text(widget.post == null ? 'Nova publicação' : 'Editar publicação'),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextBox(controller: _title, placeholder: 'Título', maxLength: 140),
          const SizedBox(height: 12),
          ComboBox<String>(
            value: _category,
            isExpanded: true,
            items: const [
              ComboBoxItem(value: 'eletronica', child: Text('Eletrônica')),
              ComboBoxItem(value: 'informatica', child: Text('Informática')),
              ComboBoxItem(value: 'robotica', child: Text('Robótica')),
              ComboBoxItem(value: 'projetos', child: Text('Projetos')),
              ComboBoxItem(value: 'dicas', child: Text('Dicas')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          const SizedBox(height: 12),
          TextBox(
            controller: _body,
            placeholder: 'Conteúdo',
            maxLines: 8,
            maxLength: 20000,
          ),
          const SizedBox(height: 12),
          TextBox(controller: _link, placeholder: 'Link HTTPS (opcional)'),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Cores.vermelho)),
          ],
        ],
      ),
    ),
    actions: [
      Button(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _save, child: const Text('Salvar')),
    ],
  );
}

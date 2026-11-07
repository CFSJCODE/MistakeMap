import 'package:fluent_ui/fluent_ui.dart';

import '../theme/control_styles.dart';
import '../theme/design_tokens.dart';
import 'platform_repository.dart';

/// A questão e a resposta são coletadas aqui; correção, pistas e permissões
/// ficam no servidor. Sair preserva respostas já confirmadas pelo servidor.
class PlatformSessionPage extends StatefulWidget {
  const PlatformSessionPage({
    super.key,
    required this.repository,
    required this.session,
  });
  final PlatformRepository repository;
  final PlatformData session;
  @override
  State<PlatformSessionPage> createState() => _PlatformSessionPageState();
}

class _PlatformSessionPageState extends State<PlatformSessionPage> {
  late PlatformData _session = widget.session;
  late final Map<String, TextEditingController> _answers = {
    for (final item in platformRows(_session['items']))
      '${item['id']}': TextEditingController(text: '${item['answer'] ?? ''}'),
  };
  final Set<String> _unsaved = {};
  List<PlatformData> _results = [];
  final Map<String, String> _hints = {};
  final Map<String, int> _hintLevels = {};
  bool _busy = false;
  String? _error;
  String? _notice;

  bool get _finished =>
      _session['status'] == 'completed' ||
      _session['status'] == 'finished' ||
      _session['finished_at'] != null;

  @override
  void initState() {
    super.initState();
    _results = platformRows(_session['results']);
    if (_finished && _results.isEmpty) _finish(alreadyFinished: true);
  }

  @override
  void dispose() {
    for (final controller in _answers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<bool> _saveItem(PlatformData item) async {
    await widget.repository.execute('save_answer', {
      'session_id': _session['id'],
      'item_id': item['id'],
      'answer': _answers['${item['id']}']!.text.trim(),
    });
    _unsaved.remove('${item['id']}');
    return true;
  }

  Future<void> _save(PlatformData item) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await _saveItem(item);
      if (mounted) {
        setState(
          () => _notice =
              'Resposta salva. Você pode continuar depois em outro aparelho.',
        );
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (mounted) {
      setState(
        () => _error = error is PlatformFailure
            ? error.message
            : 'Não foi possível salvar. Sua resposta continua nesta tela.',
      );
    }
  }

  Future<void> _finish({bool alreadyFinished = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!alreadyFinished) {
        for (final item in platformRows(_session['items'])) {
          if (_unsaved.contains('${item['id']}')) await _saveItem(item);
        }
      }
      final result = await widget.repository.execute('finish_session', {
        'session_id': _session['id'],
      });
      if (!mounted) return;
      setState(() {
        _session = platformMap(result['session']);
        _results = platformRows(result['results']);
        _notice =
            '${result['correct_count'] ?? 0} de ${result['total'] ?? _results.length} respostas equivalentes ao gabarito. Confira a resolução dos demais itens.';
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hint(PlatformData item) async {
    final id = '${item['id']}';
    final level = ((_hintLevels[id] ?? 0) + 1).clamp(1, 3);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.execute('hints', {
        'session_id': _session['id'],
        'item_id': item['id'],
        'level': level,
      });
      if (mounted) {
        setState(() {
          _hints[id] =
              '${result['hint'] ?? result['text'] ?? 'Leia o enunciado e identifique as grandezas fornecidas.'}';
          _hintLevels[id] = level;
        });
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _canLeave() async {
    if (_unsaved.isEmpty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (_) => ContentDialog(
            title: const Text('Guardar suas respostas?'),
            content: const Text(
              'Há respostas ainda não salvas no servidor. Volte à sessão para salvá-las antes de sair.',
            ),
            actions: [
              MistakeMapButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Voltar à sessão'),
              ),
              MistakeMapButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sair sem salvar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _unsaved.isEmpty,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop && await _canLeave() && mounted) {
        setState(() => _unsaved.clear());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    },
    child: NavigationView(
      content: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: MistakeMapButton(
                    onPressed: _busy ? null : () => Navigator.maybePop(context),
                    child: const Text('Voltar'),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '${_session['title'] ?? 'Sua sessão'}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _session['mode'] == 'exam'
                      ? 'Modo prova · sem pistas · respostas salvas ao tocar em Salvar'
                      : 'Modo prática · ajuda gradual disponível',
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  InfoBar(
                    title: const Text(
                      'Sua resposta está preservada nesta tela',
                    ),
                    content: Text(_error!),
                    severity: InfoBarSeverity.warning,
                  ),
                if (_notice != null)
                  InfoBar(
                    title: const Text('Sua sessão'),
                    content: Text(_notice!),
                  ),
                const SizedBox(height: 24),
                if (_finished) ...[
                  const Text(
                    'A comparação é conservadora: uma resposta diferente do gabarito pode estar correta. Confira a resolução e os passos usados; esta medida não comprova domínio do conteúdo.',
                  ),
                  const SizedBox(height: 16),
                  for (final result in _results)
                    Container(
                      padding: const EdgeInsets.all(24),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: MistakeMapDesign.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: MistakeMapDesign.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            result['verdict'] == 'correct'
                                ? 'Resposta equivalente ao gabarito'
                                : 'Confira sua resolução',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SelectableText(
                            'Sua resposta: ${result['answer'] ?? 'Sem resposta'}',
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            'Referência: ${result['correct_answer'] ?? ''}',
                          ),
                          const SizedBox(height: 8),
                          SelectableText('${result['explanation'] ?? ''}'),
                        ],
                      ),
                    ),
                ] else ...[
                  for (final (index, item) in platformRows(
                    _session['items'],
                  ).indexed)
                    Container(
                      padding: const EdgeInsets.all(24),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: MistakeMapDesign.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: MistakeMapDesign.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Questão ${index + 1} · ${item['theme']}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SelectableText('${item['prompt']}'),
                          const SizedBox(height: 16),
                          InfoLabel(
                            label: 'Sua resolução',
                            child: TextBox(
                              controller: _answers['${item['id']}'],
                              minLines: 3,
                              maxLines: 8,
                              enabled: !_busy,
                              onChanged: (_) => setState(() {
                                _unsaved.add('${item['id']}');
                                _notice = null;
                              }),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              MistakeMapFilledButton(
                                onPressed: _busy ? null : () => _save(item),
                                child: const Text('Salvar resposta'),
                              ),
                              if (_session['mode'] != 'exam')
                                MistakeMapButton(
                                  onPressed: _busy ? null : () => _hint(item),
                                  child: Text(
                                    (_hintLevels['${item['id']}'] ?? 0) >= 2
                                        ? 'Ver resolução comentada'
                                        : 'Preciso de uma pista',
                                  ),
                                ),
                            ],
                          ),
                          if (_hints.containsKey('${item['id']}')) ...[
                            const SizedBox(height: 16),
                            InfoBar(
                              title: const Text('Ajuda na prática'),
                              content: Text(_hints['${item['id']}']!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  MistakeMapFilledButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => ContentDialog(
                                title: const Text('Finalizar sessão?'),
                                content: const Text(
                                  'As respostas serão salvas e a devolutiva será liberada. Depois disso, esta sessão não poderá ser editada.',
                                ),
                                actions: [
                                  MistakeMapButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Continuar respondendo'),
                                  ),
                                  MistakeMapFilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Finalizar'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) await _finish();
                          },
                    child: Text(_busy ? 'Salvando…' : 'Finalizar e conferir'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

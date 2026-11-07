import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../theme/control_styles.dart';
import 'platform_repository.dart';

class PlatformField {
  const PlatformField(
    this.key,
    this.label, {
    this.required = true,
    this.multiline = false,
    this.initial = '',
    this.hint,
  });
  final String key;
  final String label;
  final bool required;
  final bool multiline;
  final String initial;
  final String? hint;
}

/// Fluent's checkbox leaves its content unconstrained. Give long labels the
/// available width so text scaling and narrow dialogs remain readable.
class PlatformCheck extends StatelessWidget {
  const PlatformCheck({
    super.key,
    required this.content,
    required this.checked,
    required this.onChanged,
  });
  final Widget content;
  final bool checked;
  final ValueChanged<bool?>? onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Checkbox(
        checked: checked,
        onChanged: onChanged,
        content: SizedBox(
          width: (box.maxWidth - 40).clamp(0, double.infinity),
          child: content,
        ),
      ),
    ),
  );
}

class PlatformFormDialog extends StatefulWidget {
  const PlatformFormDialog({
    super.key,
    required this.title,
    required this.fields,
    required this.onSave,
    this.requireRights = false,
    this.confirmations = const {},
  });
  final String title;
  final List<PlatformField> fields;
  final Future<void> Function(Map<String, String>) onSave;
  final bool requireRights;
  final Map<String, String> confirmations;
  @override
  State<PlatformFormDialog> createState() => _PlatformFormDialogState();
}

class _PlatformFormDialogState extends State<PlatformFormDialog> {
  late final _controllers = {
    for (final field in widget.fields)
      field.key: TextEditingController(text: field.initial),
  };
  bool _saving = false;
  bool _rightsConfirmed = false;
  final _confirmed = <String>{};
  String? _error;
  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final values = {
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    };
    if (widget.requireRights) {
      if (!_rightsConfirmed) {
        setState(() => _error = 'Confirme que você pode usar este material.');
        return;
      }
      values['rights_confirmed'] = 'true';
    }
    for (final key in widget.confirmations.keys) {
      if (!_confirmed.contains(key)) {
        setState(() => _error = 'Conclua as conferências antes de publicar.');
        return;
      }
      values[key] = 'true';
    }
    if (widget.fields.any(
      (field) => field.required && values[field.key]!.isEmpty,
    )) {
      setState(() => _error = 'Preencha os campos obrigatórios.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(values);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PlatformFailure
              ? error.message
              : 'Não foi possível salvar. Seus dados permanecem no formulário.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ContentDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final field in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InfoLabel(
                label: '${field.label}${field.required ? ' *' : ''}',
                child: TextBox(
                  controller: _controllers[field.key],
                  placeholder: field.hint,
                  minLines: field.multiline ? 3 : 1,
                  maxLines: field.multiline ? 6 : 1,
                  enabled: !_saving,
                ),
              ),
            ),
          if (widget.requireRights)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: PlatformCheck(
                checked: _rightsConfirmed,
                content: const Text(
                  'Tenho autorização para usar este material pessoalmente.',
                ),
                onChanged: _saving
                    ? null
                    : (value) =>
                          setState(() => _rightsConfirmed = value == true),
              ),
            ),
          for (final confirmation in widget.confirmations.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: PlatformCheck(
                content: Text(confirmation.value),
                checked: _confirmed.contains(confirmation.key),
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          _confirmed.add(confirmation.key);
                        } else {
                          _confirmed.remove(confirmation.key);
                        }
                      }),
              ),
            ),
          if (_error != null)
            InfoBar(
              title: const Text('Confira os dados'),
              content: Text(_error!),
              severity: InfoBarSeverity.warning,
            ),
        ],
      ),
    ),
    actions: [
      MistakeMapButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancelar'),
      ),
      MistakeMapFilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Salvando…' : 'Salvar'),
      ),
    ],
  );
}

class PlatformExportDialog extends StatefulWidget {
  const PlatformExportDialog({
    super.key,
    required this.repository,
    required this.initial,
  });
  final PlatformRepository repository;
  final PlatformData initial;
  @override
  State<PlatformExportDialog> createState() => _PlatformExportDialogState();
}

class _PlatformExportDialogState extends State<PlatformExportDialog> {
  late PlatformData _page = widget.initial;
  String? _error;
  bool _busy = false;
  List<String> get _tables =>
      (_page['tables'] as List? ?? []).map((v) => '$v').toList();
  Future<void> _next([String? table]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = await widget.repository.execute('export_data', {
        'table': table ?? _page['table'],
        'cursor': table == null ? _page['next_cursor'] : 0,
      });
      if (mounted) setState(() => _page = next);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ContentDialog(
    title: const Text('Exportar meus dados'),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'A exportação é dividida em páginas por tabela. Copie cada página e use Próxima página até concluir. Guarde o arquivo em local privado.',
          ),
          const SizedBox(height: 16),
          if (_tables.isNotEmpty)
            InfoLabel(
              label: 'Conjunto de dados',
              child: ComboBox<String>(
                isExpanded: true,
                value: _tables.contains(_page['table'])
                    ? _page['table'] as String
                    : null,
                items: [
                  for (final table in _tables)
                    ComboBoxItem(value: table, child: Text(table)),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) _next(value);
                      },
              ),
            ),
          const SizedBox(height: 16),
          SelectableText(const JsonEncoder.withIndent('  ').convert(_page)),
          if (_page['next_cursor'] == null)
            const Text(
              'Última página deste conjunto. Selecione os outros conjuntos para completar sua exportação.',
            ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      MistakeMapButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Fechar'),
      ),
      MistakeMapButton(
        onPressed: () => Clipboard.setData(
          ClipboardData(
            text: const JsonEncoder.withIndent('  ').convert(_page),
          ),
        ),
        child: const Text('Copiar página'),
      ),
      if (_page['next_cursor'] != null)
        MistakeMapFilledButton(
          onPressed: _busy ? null : () => _next(),
          child: const Text('Próxima página'),
        ),
    ],
  );
}

class PlatformAssignmentDialog extends StatefulWidget {
  const PlatformAssignmentDialog({
    super.key,
    required this.repository,
    required this.classId,
    required this.catalog,
  });
  final PlatformRepository repository;
  final String classId;
  final List<PlatformData> catalog;
  @override
  State<PlatformAssignmentDialog> createState() =>
      _PlatformAssignmentDialogState();
}

class PlatformWeekDialog extends StatefulWidget {
  const PlatformWeekDialog({
    super.key,
    required this.repository,
    required this.initial,
  });
  final PlatformRepository repository;
  final PlatformData initial;
  @override
  State<PlatformWeekDialog> createState() => _PlatformWeekDialogState();
}

class _PlatformWeekDialogState extends State<PlatformWeekDialog> {
  late PlatformData _summary = widget.initial;
  bool _busy = false;
  String? _error;
  Future<void> _protect(String date) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.execute('freeze_streak', {
        'date': date,
      });
      if (mounted) setState(() => _summary = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PlatformFailure
              ? error.message
              : 'Não foi possível preservar a sequência.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final period = platformMap(_summary['period']);
    final review = platformMap(_summary['review']);
    final practice = platformMap(_summary['practice']);
    final streak = platformMap(_summary['streak']);
    return ContentDialog(
      title: const Text('Seu resumo semanal'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (period.isEmpty)
              const Text('Ainda não foi possível carregar seu resumo.')
            else ...[
              Text('${period['start_date']} a ${period['end_date']}'),
              const SizedBox(height: 16),
              Text(
                'Revisões: ${review['reviews']} autoavaliações; em ${review['recalled']} você relatou lembrar.',
              ),
              const SizedBox(height: 8),
              Text(
                'Prática sem pistas: ${practice['matched_reference']} respostas equivalentes à referência em ${practice['new_unassisted_answered']} questões novas respondidas.',
              ),
              const SizedBox(height: 16),
              Text(
                'Sequência: ${streak['current_days']} dias · ${streak['protected_days']} protegidos',
              ),
              for (final date
                  in (streak['freeze_eligible_dates'] as List? ?? [])) ...[
                const SizedBox(height: 8),
                MistakeMapButton(
                  onPressed: _busy ? null : () => _protect('$date'),
                  child: Text('Preservar pausa de $date'),
                ),
              ],
              const SizedBox(height: 16),
              for (final item in platformRows(
                _summary['achievements'],
              ).where((item) => item['earned'] == true)) ...[
                Text(
                  '${item['label']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text('${item['description']}'),
                const SizedBox(height: 8),
              ],
              if (_summary['notice'] != null) Text('${_summary['notice']}'),
              if (_summary['freeze_date'] != null)
                const Text(
                  'Pausa preservada. Ela não conta como um dia estudado.',
                ),
            ],
            if (_error != null) Text(_error!),
          ],
        ),
      ),
      actions: [
        MistakeMapButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _PlatformAssignmentDialogState extends State<PlatformAssignmentDialog> {
  final _title = TextEditingController();
  final _date = TextEditingController();
  final _selected = <String>{};
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _title.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _selected.isEmpty) {
      setState(
        () => _error = 'Informe o título e selecione pelo menos uma questão.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.execute('create_assignment', {
        'class_id': widget.classId,
        'title': _title.text.trim(),
        'due_at': _date.text.trim().isEmpty
            ? null
            : '${_date.text.trim()}T23:59:00Z',
        'catalog_ids': _selected.toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PlatformFailure
              ? error.message
              : 'Não foi possível atribuir a lista.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ContentDialog(
    title: const Text('Lista para a turma'),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoLabel(
            label: 'Título',
            child: TextBox(controller: _title, enabled: !_busy),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Prazo opcional (AAAA-MM-DD)',
            child: TextBox(controller: _date, enabled: !_busy),
          ),
          const SizedBox(height: 16),
          const Text('Selecione as questões que os estudantes receberão.'),
          const SizedBox(height: 8),
          if (widget.catalog.isEmpty)
            const Text(
              'Nenhuma questão encontrada. Volte à Biblioteca e ajuste a busca.',
            ),
          for (final item in widget.catalog)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: PlatformCheck(
                content: Text(
                  '${item['subject']} · ${item['theme']}\n${item['prompt_text']}',
                ),
                checked: _selected.contains('${item['id']}'),
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          _selected.add('${item['id']}');
                        } else {
                          _selected.remove('${item['id']}');
                        }
                      }),
              ),
            ),
          if (_error != null)
            InfoBar(
              title: const Text('Confira a lista'),
              content: Text(_error!),
              severity: InfoBarSeverity.warning,
            ),
        ],
      ),
    ),
    actions: [
      MistakeMapButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('Cancelar'),
      ),
      MistakeMapFilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Salvando…' : 'Atribuir lista'),
      ),
    ],
  );
}

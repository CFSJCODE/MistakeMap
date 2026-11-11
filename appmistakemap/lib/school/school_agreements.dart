// Contrato e LGPD da escola (onda 1, item E).
//
// O dono lê e aceita, com versão e data, os Termos de Uso, o Contrato SaaS e
// o Acordo de Tratamento de Dados. Até o aceite, o servidor bloqueia o uso da
// escola (convites, turmas e matrículas). A regra fica toda no banco
// (migration 20261111074500_school_agreements): o app só mostra o texto
// vigente que o servidor devolve e envia a versão e o hash do que mostrou.

import 'package:fluent_ui/fluent_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../platform/platform_forms.dart' show PlatformCheck;
import '../theme/control_styles.dart';
import '../theme/design_tokens.dart';

/// Um documento vigente e, se já aceito pela escola, quando e por quem.
class SchoolAgreementDocument {
  const SchoolAgreementDocument({
    required this.document,
    required this.version,
    required this.title,
    required this.body,
    required this.sha256,
    required this.effectiveAt,
    this.acceptedAt,
    this.signerName,
    this.signerRole,
  });

  factory SchoolAgreementDocument.fromRow(Map<String, dynamic> row) =>
      SchoolAgreementDocument(
        document: row['document'] as String,
        version: row['version'] as String,
        title: row['title'] as String,
        body: row['body'] as String? ?? '',
        sha256: row['sha256'] as String,
        effectiveAt: DateTime.parse(row['effective_at'] as String).toLocal(),
        acceptedAt: row['accepted_at'] == null
            ? null
            : DateTime.parse(row['accepted_at'] as String).toLocal(),
        signerName: row['signer_name'] as String?,
        signerRole: row['signer_role'] as String?,
      );

  final String document;
  final String version;
  final String title;
  final String body;
  final String sha256;
  final DateTime effectiveAt;
  final DateTime? acceptedAt;
  final String? signerName;
  final String? signerRole;

  bool get accepted => acceptedAt != null;

  /// O que o servidor confere no aceite: o texto mostrado é o vigente.
  Map<String, String> get shown => {
    'document': document,
    'version': version,
    'sha256': sha256,
  };
}

class SchoolAgreementFailure implements Exception {
  const SchoolAgreementFailure(this.message, {this.outdated = false});
  final String message;

  /// Os textos mudaram enquanto a tela estava aberta: recarregar.
  final bool outdated;
  @override
  String toString() => message;
}

abstract class SchoolAgreementsRepository {
  Future<List<SchoolAgreementDocument>> status(String schoolId);

  /// Devolve se a escola ficou liberada.
  Future<bool> accept(
    String schoolId,
    List<SchoolAgreementDocument> documents, {
    required String signerName,
    required String signerRole,
  });
}

class SupabaseSchoolAgreementsRepository implements SchoolAgreementsRepository {
  SupabaseSchoolAgreementsRepository(this.client);
  final SupabaseClient client;

  @override
  Future<List<SchoolAgreementDocument>> status(String schoolId) async {
    try {
      final rows = await client.rpc(
        'school_agreement_status',
        params: {'p_school': schoolId},
      );
      return [
        for (final row in rows as List)
          SchoolAgreementDocument.fromRow(Map<String, dynamic>.from(row)),
      ];
    } on PostgrestException catch (error) {
      throw schoolAgreementFailure(error.code);
    } catch (_) {
      throw schoolAgreementFailure(null);
    }
  }

  @override
  Future<bool> accept(
    String schoolId,
    List<SchoolAgreementDocument> documents, {
    required String signerName,
    required String signerRole,
  }) async {
    try {
      final usable = await client.rpc(
        'accept_school_agreements',
        params: {
          'p_school': schoolId,
          'p_documents': [for (final d in documents) d.shown],
          'p_signer_name': signerName,
          'p_signer_role': signerRole,
        },
      );
      return usable == true;
    } on PostgrestException catch (error) {
      throw schoolAgreementFailure(error.code);
    } catch (_) {
      throw schoolAgreementFailure(null);
    }
  }
}

/// Traduz os códigos de erro da migration para uma frase da tela.
SchoolAgreementFailure schoolAgreementFailure(String? code) => switch (code) {
  'MM409' => const SchoolAgreementFailure(
    'Os textos foram atualizados enquanto você lia. Carregamos a versão nova: confira e aceite de novo.',
    outdated: true,
  ),
  'MM403' => const SchoolAgreementFailure(
    'Só o dono da escola pode aceitar o contrato.',
  ),
  'MM401' => const SchoolAgreementFailure(
    'Sua sessão expirou. Entre de novo para continuar.',
  ),
  '22023' => const SchoolAgreementFailure(
    'Informe o nome completo e o cargo de quem aceita pela escola.',
  ),
  _ => const SchoolAgreementFailure(
    'Não foi possível falar com o servidor. Verifique sua conexão e tente novamente.',
  ),
};

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';

/// Tela de contrato da escola. O dono aceita; o coordenador só consulta.
class SchoolAgreementsPage extends StatefulWidget {
  const SchoolAgreementsPage({
    super.key,
    required this.schoolId,
    required this.schoolName,
    required this.repository,
    required this.isOwner,
    this.onAccepted,
  });

  final String schoolId;
  final String schoolName;
  final SchoolAgreementsRepository repository;
  final bool isOwner;

  /// Chamado quando o aceite libera a escola.
  final VoidCallback? onAccepted;

  @override
  State<SchoolAgreementsPage> createState() => _SchoolAgreementsPageState();
}

class _SchoolAgreementsPageState extends State<SchoolAgreementsPage> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _read = <String>{};
  List<SchoolAgreementDocument> _documents = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  Future<void> _load({String? keepError}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final documents = await widget.repository.status(widget.schoolId);
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _read.removeWhere(
          (key) => !documents.any((d) => _key(d) == key && !d.accepted),
        );
        _formError = keepError;
      });
    } on SchoolAgreementFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _key(SchoolAgreementDocument d) => '${d.document}@${d.version}';

  List<SchoolAgreementDocument> get _pending => [
    for (final d in _documents)
      if (!d.accepted) d,
  ];

  Future<void> _accept() async {
    if (_saving) return;
    final pending = _pending;
    if (pending.any((d) => !_read.contains(_key(d)))) {
      setState(
        () => _formError = 'Marque que leu e aceita cada documento pendente.',
      );
      return;
    }
    final name = _name.text.trim();
    final role = _role.text.trim();
    if (name.length < 3 || role.length < 2) {
      setState(
        () => _formError =
            'Informe o nome completo e o cargo de quem aceita pela escola.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final usable = await widget.repository.accept(
        widget.schoolId,
        _documents,
        signerName: name,
        signerRole: role,
      );
      await _load();
      if (usable) widget.onAccepted?.call();
    } on SchoolAgreementFailure catch (failure) {
      if (failure.outdated) {
        await _load(keepError: failure.message);
      } else if (mounted) {
        setState(() => _formError = failure.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
                constraints: const BoxConstraints(maxWidth: 840),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: _content(),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

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
          'Contrato e privacidade',
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

  List<Widget> _content() {
    if (_loading) return const [Center(child: ProgressRing())];
    if (_error != null) {
      return [
        InfoBar(
          title: const Text('Vamos tentar de novo'),
          content: Text(_error!),
          severity: InfoBarSeverity.warning,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: MistakeMapButton(
            onPressed: _load,
            child: const Text('Atualizar'),
          ),
        ),
      ];
    }
    final pending = _pending;
    return [
      Text(
        widget.schoolName,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        'A escola é a controladora dos dados da comunidade escolar e o MistakeMap é o operador, que trata os dados só para prestar o serviço.',
      ),
      const SizedBox(height: 16),
      if (pending.isEmpty)
        InfoBar(
          title: const Text('Escola liberada'),
          content: Text(_acceptedSummary()),
          severity: InfoBarSeverity.success,
        )
      else
        InfoBar(
          title: const Text('Uso da escola bloqueado'),
          content: Text(
            widget.isOwner
                ? 'Convites, turmas e matrículas ficam liberados assim que você aceitar os documentos abaixo.'
                : 'Convites, turmas e matrículas ficam liberados quando o dono da escola aceitar os documentos abaixo.',
          ),
          severity: InfoBarSeverity.warning,
        ),
      const SizedBox(height: 24),
      for (final d in _documents) _documentCard(d),
      if (pending.isNotEmpty && widget.isOwner) _acceptCard(pending),
    ];
  }

  String _acceptedSummary() {
    final last = [
      for (final d in _documents)
        if (d.acceptedAt != null) d,
    ]..sort((a, b) => b.acceptedAt!.compareTo(a.acceptedAt!));
    if (last.isEmpty) return 'Todos os documentos vigentes foram aceitos.';
    final d = last.first;
    return 'Último aceite em ${_date(d.acceptedAt!)}, por ${d.signerName} (${d.signerRole}).';
  }

  Widget _documentCard(SchoolAgreementDocument d) => Container(
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
          d.title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          d.accepted
              ? 'Versão ${d.version} · aceita em ${_date(d.acceptedAt!)} por ${d.signerName}'
              : 'Versão ${d.version} · em vigor desde ${_date(d.effectiveAt)} · aceite pendente',
          style: TextStyle(
            color: d.accepted
                ? MistakeMapDesign.mintInk
                : MistakeMapDesign.amberInk,
          ),
        ),
        const SizedBox(height: 16),
        Expander(
          header: const Text('Ler o documento'),
          initiallyExpanded: !d.accepted && widget.isOwner,
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(child: LegalText(body: d.body)),
          ),
        ),
        if (!d.accepted && widget.isOwner) ...[
          const SizedBox(height: 12),
          PlatformCheck(
            checked: _read.contains(_key(d)),
            content: Text('Li e aceito: ${d.title} (versão ${d.version}).'),
            onChanged: _saving
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      _read.add(_key(d));
                    } else {
                      _read.remove(_key(d));
                    }
                  }),
          ),
        ],
      ],
    ),
  );

  Widget _acceptCard(List<SchoolAgreementDocument> pending) => Container(
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
        const Text(
          'Quem aceita pela escola',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ao aceitar, você declara que pode representar a escola. Guardamos a versão, a data e hora, sua conta, seu nome e seu cargo como prova da contratação.',
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Nome completo *',
          child: TextBox(controller: _name, enabled: !_saving),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Cargo na escola *',
          child: TextBox(
            controller: _role,
            placeholder: 'Ex.: diretora, mantenedor',
            enabled: !_saving,
          ),
        ),
        const SizedBox(height: 16),
        if (_formError != null) ...[
          InfoBar(
            title: const Text('Confira antes de aceitar'),
            content: Text(_formError!),
            severity: InfoBarSeverity.warning,
          ),
          const SizedBox(height: 16),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: MistakeMapFilledButton(
            onPressed: _saving ? null : _accept,
            child: Text(
              _saving
                  ? 'Registrando aceite…'
                  : pending.length == 1
                  ? 'Aceitar e liberar a escola'
                  : 'Aceitar os ${pending.length} documentos e liberar a escola',
            ),
          ),
        ),
      ],
    ),
  );
}

/// Mostra o Markdown simples dos textos legais (títulos, parágrafos e
/// tabelas dos anexos) sem depender de pacote novo.
class LegalText extends StatelessWidget {
  const LegalText({super.key, required this.body});
  final String body;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final raw in body.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty || line == '---') continue;
      if (RegExp(r'^\|[\s|:-]+\|$').hasMatch(line)) continue;
      if (line.startsWith('# ')) {
        children.add(
          _block(line.substring(2), size: 18, weight: FontWeight.w600),
        );
      } else if (line.startsWith('## ')) {
        children.add(
          _block(line.substring(3), size: 16, weight: FontWeight.w600, top: 12),
        );
      } else if (line.startsWith('|')) {
        final cells = line
            .substring(1, line.length - 1)
            .split('|')
            .map((cell) => cell.trim())
            .where((cell) => cell.isNotEmpty);
        children.add(_block(cells.join(' · ')));
      } else {
        children.add(_block(line.replaceAll('**', '')));
      }
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _block(
    String text, {
    double size = 14,
    FontWeight weight = FontWeight.w400,
    double top = 0,
  }) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 8),
    child: Text(
      text,
      style: TextStyle(fontSize: size, fontWeight: weight, height: 1.4),
    ),
  );
}

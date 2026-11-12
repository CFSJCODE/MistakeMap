import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../billing/checkout_models.dart' show formatBrl;
import '../school/escola_ui.dart';
import '../theme/design_tokens.dart';
import '../theme/glass_surface.dart';
import 'school_reports.dart';

/// Cores dos gráficos: paleta categórica validada (ordem fixa, nunca
/// ciclada), rampa sequencial azul para intensidade e cores de situação só
/// com rótulo ao lado.
abstract final class ReportColors {
  static const series = [
    Color(0xFF2A78D6),
    Color(0xFFEB6834),
    Color(0xFF1BAF7A),
  ];
  static const bar = Color(0xFF2A78D6);
  static const paid = Color(0xFF0CA30C);
  static const open = Color(0xFFFAB219);
  static const grid = Color(0x1F11212D);
  static const ramp = [
    Color(0xFFF0F5FC),
    Color(0xFFCDE2FB),
    Color(0xFF9EC5F4),
    Color(0xFF6DA7EC),
    Color(0xFF3987E5),
    Color(0xFF256ABF),
    Color(0xFF184F95),
  ];

  /// Passo da rampa para t em 0..1 (0 = sem erro).
  static Color heat(double t) {
    if (t <= 0) return ramp.first;
    final i = 1 + (t.clamp(0, 1) * (ramp.length - 2)).round();
    return ramp[i.clamp(1, ramp.length - 1)];
  }

  /// Texto legível sobre a célula.
  static Color heatInk(double t) =>
      t > .5 ? const Color(0xFFFFFFFF) : MistakeMapDesign.deep;
}

enum ReportSection { pedagogical, financial }

class SchoolReportsPage extends StatefulWidget {
  const SchoolReportsPage({
    super.key,
    required this.schoolId,
    required this.schoolName,
    required this.repository,
    this.initial,
  });

  final String schoolId;
  final String schoolName;
  final SchoolReportsRepository repository;
  final ReportSection? initial;

  @override
  State<SchoolReportsPage> createState() => _SchoolReportsPageState();
}

class _SchoolReportsPageState extends State<SchoolReportsPage> {
  SchoolReport? _report;
  String? _error;
  bool _loading = true;
  int _months = 12;
  ReportSection? _section;
  String? _copied;

  @override
  void initState() {
    super.initState();
    _section = widget.initial;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.repository.load(widget.schoolId, months: _months);
      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
        if (_section == ReportSection.pedagogical && r.pedagogical == null) {
          _section = null;
        }
        if (_section == ReportSection.financial && r.financial == null) {
          _section = null;
        }
        _section ??= r.pedagogical != null
            ? ReportSection.pedagogical
            : ReportSection.financial;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SchoolReportsFailure
            ? e.message
            : 'Não foi possível carregar os relatórios agora.';
      });
    }
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = what);
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return NavigationView(
      content: AuroraBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _header(r),
                  if (_copied != null)
                    AvisoEscola('$_copied copiado.', sucesso: true),
                  if (_error != null) AvisoEscola(_error!),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: ProgressRing()),
                    )
                  else if (r != null) ...[
                    if (r.pedagogical != null && r.financial != null)
                      _sectionPicker(),
                    if (_section == ReportSection.pedagogical &&
                        r.pedagogical != null)
                      _PedagogicalView(
                        report: r.pedagogical!,
                        onCopyCsv: () => _copy(
                          usageCsv(r.pedagogical!),
                          'Uso por mês (CSV)',
                        ),
                      ),
                    if (_section == ReportSection.financial &&
                        r.financial != null)
                      _FinancialView(
                        report: r.financial!,
                        onCopyCsv: () =>
                            _copy(invoicesCsv(r.financial!), 'Faturas (CSV)'),
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

  Widget _header(SchoolReport? r) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Voltar',
              child: IconButton(
                icon: const Icon(FluentIcons.back, size: 18),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Relatórios',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: MistakeMapDesign.primary,
                    ),
                  ),
                  Text(
                    r?.schoolName ?? widget.schoolName,
                    style: const TextStyle(color: MistakeMapDesign.steel),
                  ),
                ],
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ComboBox<int>(
              value: _months,
              items: const [
                ComboBoxItem(value: 6, child: Text('Últimos 6 meses')),
                ComboBoxItem(value: 12, child: Text('Últimos 12 meses')),
                ComboBoxItem(value: 24, child: Text('Últimos 24 meses')),
              ],
              onChanged: _loading
                  ? null
                  : (v) {
                      if (v == null || v == _months) return;
                      setState(() => _months = v);
                      _load();
                    },
            ),
            if (r != null)
              Tooltip(
                message: 'Copiar resumo',
                child: IconButton(
                  icon: const Icon(FluentIcons.copy, size: 18),
                  onPressed: () => _copy(reportSummary(r), 'Resumo'),
                ),
              ),
            Tooltip(
              message: 'Atualizar',
              child: IconButton(
                icon: const Icon(FluentIcons.refresh, size: 18),
                onPressed: _loading ? null : _load,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _sectionPicker() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Wrap(
      children: [
        for (final s in ReportSection.values) ...[
          ToggleButton(
            checked: _section == s,
            onChanged: (_) => setState(() => _section = s),
            child: Text(
              s == ReportSection.pedagogical ? 'Pedagógico' : 'Financeiro',
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

// ------------------------------------------------------------------ pedagógico

class _PedagogicalView extends StatelessWidget {
  const _PedagogicalView({required this.report, required this.onCopyCsv});
  final PedagogicalReport report;
  final VoidCallback onCopyCsv;

  @override
  Widget build(BuildContext context) {
    final cur = report.current;
    final usage = report.usage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (report.sample) const _SampleNote(),
        _KpiRow([
          _Kpi(
            'Alunos ativos no mês',
            cur == null ? '—' : formatInt(cur.activeStudents),
          ),
          _Kpi('Análises no mês', cur == null ? '—' : formatInt(cur.analyses)),
          _Kpi('Práticas no mês', cur == null ? '—' : formatInt(cur.practices)),
          _Kpi('Turmas', formatInt(report.classes.length)),
        ]),
        CartaoEscola(
          titulo: 'Alunos ativos por mês',
          subtitulo:
              'Aluno ativo é quem usou o MistakeMap no mês. É a base da '
              'cobrança.',
          children: [
            _MonthBars(
              values: [for (final u in usage) u.activeStudents.toDouble()],
              months: [for (final u in usage) u.month],
              color: ReportColors.bar,
              format: (v) => '${formatInt(v.round())} alunos',
              semantics: 'Alunos ativos por mês',
            ),
            Align(
              alignment: Alignment.centerRight,
              child: HyperlinkButton(
                onPressed: usage.isEmpty ? null : onCopyCsv,
                child: const Text('Copiar tabela (CSV)'),
              ),
            ),
          ],
        ),
        CartaoEscola(
          titulo: 'Análises de erro por mês',
          subtitulo: 'Cada resolução enviada e analisada pela IA.',
          children: [
            _MonthBars(
              values: [for (final u in usage) u.analyses.toDouble()],
              months: [for (final u in usage) u.month],
              color: ReportColors.series[2],
              format: (v) => '${formatInt(v.round())} análises',
              semantics: 'Análises por mês',
            ),
          ],
        ),
        CartaoEscola(
          titulo: 'Práticas por mês',
          subtitulo: 'Treinos gerados a partir do mapa de erros.',
          children: [
            _MonthBars(
              values: [for (final u in usage) u.practices.toDouble()],
              months: [for (final u in usage) u.month],
              color: ReportColors.series[1],
              format: (v) => '${formatInt(v.round())} práticas',
              semantics: 'Práticas por mês',
            ),
          ],
        ),
        CartaoEscola(
          titulo: 'Mapa de erros da escola',
          subtitulo:
              'Últimos 90 dias, só com totais. Aparece com 5 ou mais alunos '
              'com erro; cada conceito, com 3 ou mais.',
          children: [
            if (report.errorTypes.isEmpty)
              Text(
                report.errorStudents == 0
                    ? 'Ainda não há erros analisados de alunos da escola.'
                    : 'Por privacidade, o mapa aparece quando 5 ou mais alunos '
                          'tiverem erros analisados (hoje: '
                          '${report.errorStudents}).',
                style: const TextStyle(color: MistakeMapDesign.content),
              )
            else ...[
              const _Subtitle('Erros por tipo'),
              _HorizontalBars(
                rows: [
                  for (final t in report.errorTypes)
                    _HBar(
                      errorTypeLabel(t.type),
                      t.errors.toDouble(),
                      '${formatInt(t.errors)} erros · '
                      '${formatInt(t.students)} alunos',
                    ),
                ],
                color: ReportColors.bar,
              ),
              if (report.concepts.isNotEmpty) ...[
                const SizedBox(height: 20),
                const _Subtitle('Conceitos × tipo de erro'),
                _Heatmap(report: report),
              ],
            ],
          ],
        ),
        CartaoEscola(
          titulo: 'Turmas',
          subtitulo: 'Alunos que usaram nos últimos 28 dias.',
          children: [
            if (report.classes.isEmpty)
              const Text(
                'Nenhuma turma ligada à escola ainda.',
                style: TextStyle(color: MistakeMapDesign.content),
              )
            else
              for (final c in report.classes) _ClassRow(c),
          ],
        ),
      ],
    );
  }
}

class _ClassRow extends StatelessWidget {
  const _ClassRow(this.c);
  final ClassReport c;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(
              c.title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: MistakeMapDesign.deep,
              ),
            ),
            Text(
              '${formatInt(c.active28d)} de ${formatInt(c.students)} ativos · '
              '${c.assignments} tarefas',
              style: const TextStyle(color: MistakeMapDesign.steel),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          label:
              '${c.title}: ${(c.activeShare * 100).round()}% dos alunos '
              'ativos',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: MistakeMapDesign.well),
                  FractionallySizedBox(
                    widthFactor: c.activeShare.clamp(0, 1),
                    child: Container(color: ReportColors.bar),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.report});
  final PedagogicalReport report;

  @override
  Widget build(BuildContext context) {
    final types = report.conceptTypes;
    final maxCell = report.concepts
        .expand((c) => c.byType.values)
        .fold<int>(1, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(92),
            columnWidths: const {0: FixedColumnWidth(170)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  const SizedBox(),
                  for (final t in types)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        errorTypeLabel(t),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: MistakeMapDesign.steel,
                        ),
                      ),
                    ),
                ],
              ),
              for (final c in report.concepts)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        c.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: MistakeMapDesign.deep),
                      ),
                    ),
                    for (final t in types) _cell(c, t, maxCell),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Menos',
              style: TextStyle(fontSize: 12, color: MistakeMapDesign.steel),
            ),
            const SizedBox(width: 6),
            for (final c in ReportColors.ramp.skip(1))
              Container(
                width: 18,
                height: 10,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            const SizedBox(width: 4),
            const Text(
              'Mais erros',
              style: TextStyle(fontSize: 12, color: MistakeMapDesign.steel),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cell(ConceptReport c, String type, int maxCell) {
    final n = c.byType[type] ?? 0;
    final t = n / maxCell;
    return Tooltip(
      message: '${c.title} · ${errorTypeLabel(type)}: ${formatInt(n)} erros',
      child: Container(
        height: 36,
        margin: const EdgeInsets.all(1),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ReportColors.heat(n == 0 ? 0 : t),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          n == 0 ? '' : formatInt(n),
          style: TextStyle(fontSize: 12, color: ReportColors.heatInk(t)),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ financeiro

class _FinancialView extends StatelessWidget {
  const _FinancialView({required this.report, required this.onCopyCsv});
  final FinancialReport report;
  final VoidCallback onCopyCsv;

  @override
  Widget build(BuildContext context) {
    final perStudent = report.costPerActiveStudent;
    final current = report.currentCost;
    final byMonth = report.invoicesByMonth;
    final methodTotal = report.byMethod.fold<double>(0, (s, m) => s + m.total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (report.sample) const _SampleNote(),
        _KpiRow([
          _Kpi('Pago no período', formatBrl(report.paidTotal)),
          _Kpi('Em aberto', formatBrl(report.openTotal)),
          _Kpi(
            'Custo por aluno ativo',
            perStudent == null ? '—' : formatBrl(perStudent),
            note: 'média mensal',
          ),
          _Kpi(
            'Mês atual (prévia)',
            current == null ? '—' : formatBrl(current.total),
            note: current == null
                ? null
                : '${formatInt(current.activeStudents)} alunos ativos',
          ),
        ]),
        CartaoEscola(
          titulo: 'Custo pelo uso',
          subtitulo:
              'Quanto cada mês custa pelos alunos ativos, com a mesma conta da '
              'fatura (preço por aluno e desconto por volume).',
          children: [
            _MonthBars(
              values: [for (final c in report.cost) c.total],
              months: [for (final c in report.cost) c.month],
              color: ReportColors.bar,
              format: formatBrl,
              semantics: 'Custo pelo uso por mês',
            ),
          ],
        ),
        CartaoEscola(
          titulo: 'Faturas por mês',
          subtitulo: 'Pago e em aberto em cada mês de referência.',
          children: [
            if (byMonth.isEmpty)
              const Text(
                'Nenhuma fatura no período.',
                style: TextStyle(color: MistakeMapDesign.content),
              )
            else ...[
              _Legend([
                ('Pago', ReportColors.paid),
                ('Em aberto', ReportColors.open),
              ]),
              const SizedBox(height: 8),
              _StackedMonthBars(months: byMonth),
            ],
          ],
        ),
        CartaoEscola(
          titulo: 'Forma de pagamento',
          subtitulo: 'Valor pago em cada forma no período.',
          children: [
            if (report.byMethod.isEmpty)
              const Text(
                'Nenhum pagamento no período.',
                style: TextStyle(color: MistakeMapDesign.content),
              )
            else
              Wrap(
                spacing: 24,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    label: 'Gráfico de rosca das formas de pagamento',
                    child: SizedBox(
                      width: 150,
                      height: 150,
                      child: CustomPaint(
                        painter: _DonutPainter([
                          for (final (i, m) in report.byMethod.indexed)
                            (m.total, _methodColor(m.method, i)),
                        ]),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, m) in report.byMethod.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LegendItem(
                            color: _methodColor(m.method, i),
                            label:
                                '${m.label}: ${formatBrl(m.total)} · '
                                '${m.count} '
                                '${m.count == 1 ? 'pagamento' : 'pagamentos'}'
                                '${methodTotal > 0 ? ' · ${(m.total / methodTotal * 100).round()}%' : ''}',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
          ],
        ),
        CartaoEscola(
          titulo: 'Situação das faturas',
          children: [
            if (report.byStatus.isEmpty)
              const Text(
                'Nenhuma fatura no período.',
                style: TextStyle(color: MistakeMapDesign.content),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in report.byStatus)
                    _Chip(
                      '${s.label}: ${s.count} · ${formatBrl(s.total)}',
                      icon: switch (s.status) {
                        'paid' => FluentIcons.completed,
                        'overdue' || 'failed' => FluentIcons.warning,
                        'canceled' => FluentIcons.cancel,
                        _ => FluentIcons.clock,
                      },
                    ),
                ],
              ),
          ],
        ),
        CartaoEscola(
          titulo: 'Faturas',
          subtitulo: 'As mais recentes primeiro.',
          children: [
            if (report.invoices.isEmpty)
              const Text(
                'Nenhuma fatura no período.',
                style: TextStyle(color: MistakeMapDesign.content),
              )
            else ...[
              for (final i in report.invoices.take(12)) _InvoiceRow(i),
              Align(
                alignment: Alignment.centerRight,
                child: HyperlinkButton(
                  onPressed: onCopyCsv,
                  child: const Text('Copiar faturas (CSV)'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  static Color _methodColor(String method, int i) => switch (method) {
    'boleto' => ReportColors.series[0],
    'pix' => ReportColors.series[2],
    'credit_card' => ReportColors.series[1],
    _ => ReportColors.series[i % ReportColors.series.length],
  };
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow(this.i);
  final InvoiceReport i;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: MistakeMapDesign.hairline)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${monthLabel(i.referenceMonth)} · '
                '${i.kind == 'checkout' ? 'Contratação' : 'Mensal'} · '
                '${formatInt(i.students)} alunos',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: MistakeMapDesign.deep,
                ),
              ),
              Text(
                '${paymentMethodLabels[i.method] ?? i.method} · '
                '${invoiceStatusLabels[i.status] ?? i.status}'
                '${i.nfseNumber == null ? '' : ' · NFS-e ${i.nfseNumber}'}'
                '${i.purchaseOrder == null ? '' : ' · ${i.purchaseOrder}'}',
                style: const TextStyle(color: MistakeMapDesign.steel),
              ),
            ],
          ),
        ),
        Text(
          formatBrl(i.total),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: MistakeMapDesign.deep,
          ),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ peças

class _SampleNote extends StatelessWidget {
  const _SampleNote();
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: MistakeMapDesign.amber.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: MistakeMapDesign.amber.withValues(alpha: .5)),
    ),
    child: const Row(
      children: [
        Icon(FluentIcons.info, color: MistakeMapDesign.amberInk, size: 16),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Dados de demonstração: escola fictícia, sem alunos nem cobranças '
            'reais.',
            style: TextStyle(color: MistakeMapDesign.amberInk),
          ),
        ),
      ],
    ),
  );
}

class _Kpi {
  const _Kpi(this.label, this.value, {this.note});
  final String label;
  final String value;
  final String? note;
}

class _KpiRow extends StatelessWidget {
  const _KpiRow(this.items);
  final List<_Kpi> items;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 760 ? 4 : 2;
        final w = (box.maxWidth - 12 * (cols - 1)) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final k in items)
              Container(
                width: w,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: MistakeMapDesign.surface,
                  border: Border.all(color: MistakeMapDesign.border),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      k.label,
                      style: const TextStyle(color: MistakeMapDesign.steel),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        k.value,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: MistakeMapDesign.primary,
                        ),
                      ),
                    ),
                    if (k.note != null)
                      Text(
                        k.note!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: MistakeMapDesign.steel,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _Subtitle extends StatelessWidget {
  const _Subtitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: MistakeMapDesign.deep,
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.icon});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: MistakeMapDesign.well,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: MistakeMapDesign.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: MistakeMapDesign.steel),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(color: MistakeMapDesign.deep),
          ),
        ),
      ],
    ),
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          label,
          style: const TextStyle(color: MistakeMapDesign.deep),
        ),
      ),
    ],
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.items);
  final List<(String, Color)> items;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 8,
    children: [
      for (final (label, color) in items)
        _LegendItem(color: color, label: label),
    ],
  );
}

/// Barras por mês, uma série. O valor aparece no toque/hover e o último mês
/// leva o rótulo direto.
class _MonthBars extends StatelessWidget {
  const _MonthBars({
    required this.values,
    required this.months,
    required this.color,
    required this.format,
    required this.semantics,
  });
  final List<double> values;
  final List<DateTime> months;
  final Color color;
  final String Function(double) format;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const Text(
        'Sem dados no período.',
        style: TextStyle(color: MistakeMapDesign.content),
      );
    }
    final maxV = values.fold<double>(0, math.max);
    return Semantics(
      label:
          '$semantics: ${[for (var i = 0; i < values.length; i++) '${monthLabel(months[i])} ${format(values[i])}'].join(', ')}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${monthLabel(months.last)}: ${format(values.last)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: MistakeMapDesign.deep,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: Stack(
                children: [
                  for (final f in const [0.0, .5, 1.0])
                    Align(
                      alignment: Alignment(0, 1 - 2 * f),
                      child: Container(height: 1, color: ReportColors.grid),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < values.length; i++)
                        Expanded(
                          child: Tooltip(
                            message:
                                '${monthLabel(months[i])}: ${format(values[i])}',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 1,
                              ),
                              child: FractionallySizedBox(
                                heightFactor: maxV <= 0
                                    ? 0
                                    : (values[i] / maxV).clamp(0.01, 1),
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _MonthAxis(months),
          ],
        ),
      ),
    );
  }
}

class _MonthAxis extends StatelessWidget {
  const _MonthAxis(this.months);
  final List<DateTime> months;
  @override
  Widget build(BuildContext context) {
    final every = months.length > 12 ? 3 : (months.length > 6 ? 2 : 1);
    return Row(
      children: [
        for (var i = 0; i < months.length; i++)
          Expanded(
            child: Text(
              (months.length - 1 - i) % every == 0 ? monthLabel(months[i]) : '',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: const TextStyle(
                fontSize: 11,
                color: MistakeMapDesign.steel,
              ),
            ),
          ),
      ],
    );
  }
}

class _StackedMonthBars extends StatelessWidget {
  const _StackedMonthBars({required this.months});
  final List<InvoiceMonth> months;

  @override
  Widget build(BuildContext context) {
    final maxV = months.fold<double>(0, (m, x) => math.max(m, x.paid + x.open));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 160,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final m in months)
                Expanded(
                  child: Tooltip(
                    message:
                        '${monthLabel(m.month)}: pago ${formatBrl(m.paid)}, '
                        'em aberto ${formatBrl(m.open)}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (m.open > 0)
                            Container(
                              height: maxV <= 0 ? 0 : 160 * m.open / maxV,
                              decoration: BoxDecoration(
                                color: ReportColors.open,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          if (m.open > 0 && m.paid > 0)
                            const SizedBox(height: 2),
                          if (m.paid > 0)
                            Container(
                              height: maxV <= 0
                                  ? 0
                                  : math.max(0, 160 * m.paid / maxV - 2),
                              decoration: BoxDecoration(
                                color: ReportColors.paid,
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(m.open > 0 ? 0 : 4),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _MonthAxis([for (final m in months) m.month]),
      ],
    );
  }
}

class _HBar {
  const _HBar(this.label, this.value, this.detail);
  final String label;
  final double value;
  final String detail;
}

class _HorizontalBars extends StatelessWidget {
  const _HorizontalBars({required this.rows, required this.color});
  final List<_HBar> rows;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final maxV = rows.fold<double>(0, (m, r) => math.max(m, r.value));
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.label,
                        style: const TextStyle(color: MistakeMapDesign.deep),
                      ),
                    ),
                    Text(
                      r.detail,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MistakeMapDesign.steel,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: maxV <= 0
                        ? 0
                        : (r.value / maxV).clamp(0.01, 1),
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices);
  final List<(double, Color)> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (s, x) => s + x.$1);
    if (total <= 0) return;
    final stroke = size.shortestSide * .18;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - stroke / 2,
    );
    const gap = .03;
    var start = -math.pi / 2;
    for (final (v, color) in slices) {
      final sweep = 2 * math.pi * v / total;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color;
      canvas.drawArc(
        rect,
        start + (slices.length > 1 ? gap / 2 : 0),
        math.max(0, sweep - (slices.length > 1 ? gap : 0)),
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.slices != slices;
}

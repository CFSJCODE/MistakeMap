import 'package:supabase_flutter/supabase_flutter.dart';

import '../billing/checkout_models.dart' show formatBrl;
import '../teacher/class_map_models.dart' show classMapErrorLabel;

/// Relatórios da escola (RPC school_reports). O servidor decide o que cada
/// papel vê: dono vê os dois, coordenação só o pedagógico e o
/// Financeiro/Compras só o financeiro. Nada vem por aluno.
abstract interface class SchoolReportsRepository {
  Future<SchoolReport> load(String schoolId, {int months = 12});
}

class SupabaseSchoolReportsRepository implements SchoolReportsRepository {
  SupabaseSchoolReportsRepository(this.client);
  final SupabaseClient client;

  @override
  Future<SchoolReport> load(String schoolId, {int months = 12}) async {
    try {
      final data = await client
          .rpc(
            'school_reports',
            params: {'p_school': schoolId, 'p_months': months},
          )
          .timeout(const Duration(seconds: 30));
      return SchoolReport.fromJson(_map(data));
    } on PostgrestException catch (error) {
      throw SchoolReportsFailure(
        error.code == '42501'
            ? 'Seu papel nesta escola não vê relatórios.'
            : 'Não foi possível carregar os relatórios agora.',
      );
    } catch (_) {
      throw const SchoolReportsFailure(
        'Não foi possível falar com o servidor. Confira a conexão.',
      );
    }
  }
}

class SchoolReportsFailure implements Exception {
  const SchoolReportsFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _rows(Object? v) =>
    v is List ? [for (final i in v) _map(i)] : const [];
int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _num(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');

const _months = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

/// "nov/26"
String monthLabel(DateTime m) =>
    '${_months[m.month - 1]}/${(m.year % 100).toString().padLeft(2, '0')}';

/// 1.935 (milhar com ponto, sem intl).
String formatInt(int value) {
  final s = value.abs().toString();
  final b = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

const paymentMethodLabels = {
  'pix': 'Pix',
  'boleto': 'Boleto',
  'credit_card': 'Cartão',
};

const invoiceStatusLabels = {
  'pending': 'Pendente',
  'awaiting_payment': 'Aguardando pagamento',
  'paid': 'Paga',
  'overdue': 'Vencida',
  'canceled': 'Cancelada',
  'failed': 'Recusada',
};

String errorTypeLabel(String type) => classMapErrorLabel(type);

class UsageMonth {
  const UsageMonth({
    required this.month,
    required this.activeStudents,
    required this.analyses,
    required this.practices,
    required this.closed,
  });
  factory UsageMonth.fromJson(Map<String, dynamic> j) => UsageMonth(
    month: _date(j['month']) ?? DateTime(2000),
    activeStudents: _int(j['active_students']),
    analyses: _int(j['analyses']),
    practices: _int(j['practices']),
    closed: j['closed'] == true,
  );
  final DateTime month;
  final int activeStudents;
  final int analyses;
  final int practices;
  final bool closed;
}

class ClassReport {
  const ClassReport(
    this.title,
    this.students,
    this.active28d,
    this.assignments,
  );
  factory ClassReport.fromJson(Map<String, dynamic> j) => ClassReport(
    '${j['title'] ?? 'Turma'}',
    _int(j['students']),
    _int(j['active_28d']),
    _int(j['assignments']),
  );
  final String title;
  final int students;
  final int active28d;
  final int assignments;
  double get activeShare => students == 0 ? 0 : active28d / students;
}

class ErrorTypeReport {
  const ErrorTypeReport(this.type, this.errors, this.students);
  factory ErrorTypeReport.fromJson(Map<String, dynamic> j) => ErrorTypeReport(
    '${j['error_type'] ?? 'outro'}',
    _int(j['errors']),
    _int(j['students']),
  );
  final String type;
  final int errors;
  final int students;
}

class ConceptReport {
  const ConceptReport(this.concept, this.errors, this.students, this.byType);
  factory ConceptReport.fromJson(Map<String, dynamic> j) => ConceptReport(
    '${j['concept'] ?? ''}',
    _int(j['errors']),
    _int(j['students']),
    {for (final e in _map(j['by_type']).entries) e.key: _int(e.value)},
  );
  final String concept;
  final int errors;
  final int students;
  final Map<String, int> byType;

  /// "lei de ohm" → "Lei de ohm"
  String get title => concept.isEmpty
      ? concept
      : concept[0].toUpperCase() + concept.substring(1);
}

class PedagogicalReport {
  const PedagogicalReport({
    required this.usage,
    required this.classes,
    required this.errorStudents,
    required this.errorTypes,
    required this.concepts,
    required this.sample,
  });
  factory PedagogicalReport.fromJson(
    Map<String, dynamic> j,
  ) => PedagogicalReport(
    usage: [for (final r in _rows(j['usage'])) UsageMonth.fromJson(r)],
    classes: [for (final r in _rows(j['classes'])) ClassReport.fromJson(r)],
    errorStudents: _int(j['error_students']),
    errorTypes: [
      for (final r in _rows(j['errors_by_type'])) ErrorTypeReport.fromJson(r),
    ],
    concepts: [for (final r in _rows(j['concepts'])) ConceptReport.fromJson(r)],
    sample: j['sample'] == true,
  );
  final List<UsageMonth> usage;
  final List<ClassReport> classes;
  final int errorStudents;
  final List<ErrorTypeReport> errorTypes;
  final List<ConceptReport> concepts;
  final bool sample;

  UsageMonth? get current => usage.isEmpty ? null : usage.last;

  /// Tipos que aparecem no mapa, na ordem do total de erros.
  List<String> get conceptTypes {
    final totals = <String, int>{};
    for (final c in concepts) {
      c.byType.forEach((k, v) => totals[k] = (totals[k] ?? 0) + v);
    }
    final keys = totals.keys.toList()
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    return keys;
  }
}

class CostMonth {
  const CostMonth(this.month, this.activeStudents, this.total);
  factory CostMonth.fromJson(Map<String, dynamic> j) => CostMonth(
    _date(j['month']) ?? DateTime(2000),
    _int(j['active_students']),
    _num(j['total']),
  );
  final DateTime month;
  final int activeStudents;
  final double total;
}

class InvoiceMonth {
  const InvoiceMonth(this.month, this.billed, this.paid, this.open);
  factory InvoiceMonth.fromJson(Map<String, dynamic> j) => InvoiceMonth(
    _date(j['month']) ?? DateTime(2000),
    _num(j['billed']),
    _num(j['paid']),
    _num(j['open']),
  );
  final DateTime month;
  final double billed;
  final double paid;
  final double open;
}

class MethodReport {
  const MethodReport(this.method, this.count, this.total);
  factory MethodReport.fromJson(Map<String, dynamic> j) =>
      MethodReport('${j['method'] ?? ''}', _int(j['count']), _num(j['total']));
  final String method;
  final int count;
  final double total;
  String get label => paymentMethodLabels[method] ?? method;
}

class StatusReport {
  const StatusReport(this.status, this.count, this.total);
  factory StatusReport.fromJson(Map<String, dynamic> j) =>
      StatusReport('${j['status'] ?? ''}', _int(j['count']), _num(j['total']));
  final String status;
  final int count;
  final double total;
  String get label => invoiceStatusLabels[status] ?? status;
}

class InvoiceReport {
  const InvoiceReport({
    required this.referenceMonth,
    required this.kind,
    required this.method,
    required this.status,
    required this.total,
    required this.students,
    this.dueDate,
    this.paidAt,
    this.purchaseOrder,
    this.costCenter,
    this.nfseNumber,
  });
  factory InvoiceReport.fromJson(Map<String, dynamic> j) => InvoiceReport(
    referenceMonth: _date(j['reference_month']) ?? DateTime(2000),
    kind: '${j['kind'] ?? ''}',
    method: '${j['method'] ?? ''}',
    status: '${j['status'] ?? ''}',
    total: _num(j['total']),
    students: _int(j['students']),
    dueDate: _date(j['due_date']),
    paidAt: _date(j['paid_at']),
    purchaseOrder: j['purchase_order'] as String?,
    costCenter: j['cost_center'] as String?,
    nfseNumber: j['nfse_number'] as String?,
  );
  final DateTime referenceMonth;
  final String kind;
  final String method;
  final String status;
  final double total;
  final int students;
  final DateTime? dueDate;
  final DateTime? paidAt;
  final String? purchaseOrder;
  final String? costCenter;
  final String? nfseNumber;
}

class FinancialReport {
  const FinancialReport({
    required this.cost,
    required this.invoicesByMonth,
    required this.byMethod,
    required this.byStatus,
    required this.invoices,
    required this.sample,
  });
  factory FinancialReport.fromJson(Map<String, dynamic> j) => FinancialReport(
    cost: [for (final r in _rows(j['cost_by_month'])) CostMonth.fromJson(r)],
    invoicesByMonth: [
      for (final r in _rows(j['invoices_by_month'])) InvoiceMonth.fromJson(r),
    ],
    byMethod: [for (final r in _rows(j['by_method'])) MethodReport.fromJson(r)],
    byStatus: [for (final r in _rows(j['by_status'])) StatusReport.fromJson(r)],
    invoices: [for (final r in _rows(j['invoices'])) InvoiceReport.fromJson(r)],
    sample: j['sample'] == true,
  );
  final List<CostMonth> cost;
  final List<InvoiceMonth> invoicesByMonth;
  final List<MethodReport> byMethod;
  final List<StatusReport> byStatus;
  final List<InvoiceReport> invoices;
  final bool sample;

  double get paidTotal => invoicesByMonth.fold(0, (s, m) => s + m.paid);
  double get openTotal => invoicesByMonth.fold(0, (s, m) => s + m.open);

  /// Custo médio por aluno ativo no mês (pelo uso, mesma conta da fatura).
  double? get costPerActiveStudent {
    final students = cost.fold<int>(0, (s, m) => s + m.activeStudents);
    if (students == 0) return null;
    return cost.fold<double>(0, (s, m) => s + m.total) / students;
  }

  CostMonth? get currentCost => cost.isEmpty ? null : cost.last;
}

class SchoolReport {
  const SchoolReport({
    required this.schoolName,
    required this.plan,
    required this.demo,
    required this.months,
    this.pedagogical,
    this.financial,
  });
  factory SchoolReport.fromJson(Map<String, dynamic> j) {
    final school = _map(j['school']);
    final ped = j['pedagogical'];
    final fin = j['financial'];
    return SchoolReport(
      schoolName: '${school['name'] ?? 'Escola'}',
      plan: '${school['plan'] ?? 'free'}',
      demo: school['demo'] == true,
      months: _int(j['months']),
      pedagogical: ped is Map ? PedagogicalReport.fromJson(_map(ped)) : null,
      financial: fin is Map ? FinancialReport.fromJson(_map(fin)) : null,
    );
  }
  final String schoolName;
  final String plan;
  final bool demo;
  final int months;
  final PedagogicalReport? pedagogical;
  final FinancialReport? financial;
}

String _csvCell(String v) =>
    v.contains(';') || v.contains('"') || v.contains('\n')
    ? '"${v.replaceAll('"', '""')}"'
    : v;

String _isoDate(DateTime? d) => d == null
    ? ''
    : '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

String _decimal(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

/// Faturas em CSV com ponto e vírgula (abre direto no Excel em português).
String invoicesCsv(FinancialReport report) {
  final lines = <String>[
    'Mês;Tipo;Alunos;Forma;Situação;Total (R\$);Vencimento;Pago em;'
        'Pedido de compra;Centro de custo;NFS-e',
  ];
  for (final i in report.invoices) {
    lines.add(
      [
        monthLabel(i.referenceMonth),
        i.kind == 'checkout' ? 'Contratação' : 'Mensal',
        '${i.students}',
        paymentMethodLabels[i.method] ?? i.method,
        invoiceStatusLabels[i.status] ?? i.status,
        _decimal(i.total),
        _isoDate(i.dueDate),
        _isoDate(i.paidAt),
        i.purchaseOrder ?? '',
        i.costCenter ?? '',
        i.nfseNumber ?? '',
      ].map(_csvCell).join(';'),
    );
  }
  return lines.join('\n');
}

/// Uso por mês em CSV (pedagógico).
String usageCsv(PedagogicalReport report) {
  final lines = <String>['Mês;Alunos ativos;Análises;Práticas'];
  for (final u in report.usage) {
    lines.add(
      '${monthLabel(u.month)};${u.activeStudents};${u.analyses};'
      '${u.practices}',
    );
  }
  return lines.join('\n');
}

/// Resumo curto em texto para compartilhar (e-mail, WhatsApp).
String reportSummary(SchoolReport r) {
  final b = StringBuffer('Relatório MistakeMap · ${r.schoolName}');
  if (r.demo) b.write(' (demonstração)');
  final p = r.pedagogical;
  if (p != null && p.current != null) {
    b.write(
      '\nAlunos ativos no mês: ${formatInt(p.current!.activeStudents)}'
      ' · análises: ${formatInt(p.current!.analyses)}'
      ' · práticas: ${formatInt(p.current!.practices)}',
    );
    if (p.errorTypes.isNotEmpty) {
      b.write('\nErro mais comum: ${errorTypeLabel(p.errorTypes.first.type)}');
    }
  }
  final f = r.financial;
  if (f != null) {
    b.write(
      '\nPago no período: ${formatBrl(f.paidTotal)}'
      ' · em aberto: ${formatBrl(f.openTotal)}',
    );
    final c = f.costPerActiveStudent;
    if (c != null) b.write('\nCusto médio por aluno ativo: ${formatBrl(c)}');
  }
  return b.toString();
}

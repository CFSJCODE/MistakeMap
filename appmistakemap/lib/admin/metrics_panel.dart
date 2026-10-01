import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../layout/adaptativo.dart';
import '../theme/design_tokens.dart';
import 'metrics_policy.dart';
import 'network_source.dart';
import 'free_plan.dart';
import 'model_quota_card.dart';

class AdminMetricsPanel extends StatefulWidget {
  const AdminMetricsPanel({
    super.key,
    required this.client,
    this.active = true,
    this.network,
    this.now,
    this.loadSnapshot,
  });
  final SupabaseClient client;
  final bool active;
  final NetworkKind Function()? network;
  final DateTime Function()? now;
  final Future<Map<String, dynamic>> Function()? loadSnapshot;
  @override
  State<AdminMetricsPanel> createState() => _AdminMetricsPanelState();
}

class _AdminMetricsPanelState extends State<AdminMetricsPanel>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  Timer? _clock;
  Timer? _debounce;
  RealtimeChannel? _channel;
  NetworkKind _network = NetworkKind.unknown;
  DateTime? _last;
  bool _busy = false;
  bool _foreground = true;
  bool _subscribed = false;
  final Map<String, int?> _values = {};
  String? _error;
  Map<String, dynamic>? _snapshot;
  Map<String, dynamic>? _apiSnapshot;
  bool _global = false;
  bool get _active => widget.active && _foreground;
  NetworkKind _connection() => widget.network?.call() ?? currentNetwork();
  DateTime _now() => widget.now?.call() ?? DateTime.now();
  bool _canContinue(NetworkKind started) {
    final current = _connection();
    return _active &&
        current != NetworkKind.offline &&
        (started != NetworkKind.wifi || current == NetworkKind.wifi);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 10), (_) => _sync());
    _sync();
  }

  @override
  void didUpdateWidget(AdminMetricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final network = _connection();
    if (_network != network) setState(() => _network = network);
    if (!_active || !MetricsPolicy.live(network)) {
      _debounce?.cancel();
      final channel = _channel;
      _channel = null;
      _subscribed = false;
      if (channel != null) unawaited(widget.client.removeChannel(channel));
    } else if (_channel == null) {
      final channel = widget.client.channel(
        'admin-metrics',
        opts: const RealtimeChannelConfig(private: true),
      );
      _channel = channel;
      channel.onBroadcast(
        event: 'metrics_changed',
        callback: (_) {
          if (_debounce?.isActive ?? false) return;
          _debounce = Timer(const Duration(seconds: 2), () {
            if (_active && MetricsPolicy.live(_connection())) _refresh();
          });
        },
      );
      channel.subscribe((status, error) {
        if (!mounted || _channel != channel) return;
        setState(
          () => _subscribed = status == RealtimeSubscribeStatus.subscribed,
        );
      });
    }
    if (_active &&
        (MetricsPolicy.live(network) ||
            MetricsPolicy.due(network, _last, _now()))) {
      // Wi-Fi fallback polling also covers tables without Realtime publication.
      if (_last == null ||
          _now().difference(_last!) >=
              (MetricsPolicy.live(network)
                  ? const Duration(seconds: 30)
                  : MetricsPolicy.interval)) {
        _refresh();
      }
    }
  }

  Future<void> _refresh() async {
    if (_busy || !_active || _connection() == NetworkKind.offline) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Attempt timestamps throttle failed reads too, avoiding retry storms on mobile.
    _last = _now();
    final startedOn = _connection();
    try {
      final Object data =
          await (widget.loadSnapshot?.call() ??
                  widget.client.rpc('admin_metrics_snapshot'))
              .timeout(const Duration(seconds: 10));
      if (data is Map) {
        Map<String, dynamic>? api;
        if (widget.loadSnapshot == null && _canContinue(startedOn)) {
          try {
            final response = await widget.client
                .rpc('admin_ai_api_metrics')
                .timeout(const Duration(seconds: 10));
            if (response is Map) api = Map<String, dynamic>.from(response);
          } catch (_) {
            /* Provider telemetry has its own deployment state. */
          }
        }
        if (!mounted) return;
        setState(() {
          _apiSnapshot = api;
          _snapshot = Map<String, dynamic>.from(data);
          _global = true;
          _values.addAll({
            'Total Usuários': (data['profiles'] as num?)?.toInt(),
            'Exercícios Criados': (data['exercises'] as num?)?.toInt(),
            'Tentativas & Envios': (data['attempts'] as num?)?.toInt(),
            'Em processamento': (data['processing'] as num?)?.toInt(),
          });
          _busy = false;
        });
        return;
      }
    } catch (_) {
      /* Fall back to RLS-scoped counts; never claim global access. */
    }
    _global = false;
    _snapshot = null;
    _apiSnapshot = null;
    final values = <String, int?>{};
    for (final entry in {
      'Total Usuários': 'profiles',
      'Exercícios Criados': 'exercises',
      'Tentativas & Envios': 'attempts',
    }.entries) {
      if (!_canContinue(startedOn)) break;
      try {
        values[entry.key] = await widget.client
            .from(entry.value)
            .count(CountOption.exact)
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        values[entry.key] = null;
      }
    }
    try {
      if (!_canContinue(startedOn)) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      values['Em processamento'] = await widget.client
          .from('attempts')
          .count(CountOption.exact)
          .inFilter('status', ['pending', 'processing', 'uploading'])
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      values['Em processamento'] = null;
    }
    if (!mounted) return;
    setState(() {
      _values.addAll(values);
      _busy = false;
      if (values.values.any((value) => value == null)) _error = 'Algumas métricas estão indisponíveis. A próxima leitura seguirá o intervalo da conexão.';
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _debounce?.cancel();
    if (_channel != null) unawaited(widget.client.removeChannel(_channel!));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final live = MetricsPolicy.live(_network);
    final time = _last == null
        ? 'Aguardando leitura'
        : 'Última consulta: ${_last!.hour.toString().padLeft(2, '0')}:${_last!.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Funcionamento do aplicativo',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: MistakeMapDesign.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(switch (_network) {
          NetworkKind.wifi =>
            _subscribed
                ? 'Wi-Fi · eventos em tempo real e conferência a cada 30 segundos'
                : 'Wi-Fi · conferência a cada 30 segundos; conectando eventos',
          NetworkKind.mobile => 'Dados móveis · atualização de hora em hora',
          NetworkKind.offline => 'Sem conexão · atualizações pausadas',
          NetworkKind.unknown =>
            'Tipo de conexão não identificado · atualização de hora em hora',
        }),
        const SizedBox(height: 8),
        Text('$time${_busy ? ' · Consultando…' : ''}'),
        if (!live && _last != null && _network != NetworkKind.offline)
          Text(
            'Próxima consulta: ${_last!.add(MetricsPolicy.interval).hour.toString().padLeft(2, '0')}:${_last!.minute.toString().padLeft(2, '0')}',
          ),
        const SizedBox(height: 16),
        GradeAdaptativa(
          larguraMinimaItem: 220,
          maxColunas: 4,
          children: [
            for (final label in [
              'Total Usuários',
              'Exercícios Criados',
              'Tentativas & Envios',
              'Em processamento',
            ])
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: MistakeMapDesign.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MistakeMapDesign.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    const SizedBox(height: 8),
                    Text(
                      _values[label]?.toString() ?? '—',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: MistakeMapDesign.content,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _global
              ? 'Visão global autorizada para administradores. Processamento considera somente execuções com concessão ativa.'
              : 'Contagens dos registros permitidos à conta pelo servidor. Ausência de acesso ou falha é exibida como —. Envios antigos também podem estar pendentes; este número não confirma que a IA está executando.',
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!)),
        const SizedBox(height: 24),
        const Text(
          'IA · consumo e resultados',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: MistakeMapDesign.primary,
          ),
        ),
        const SizedBox(height: 12),
        GradeAdaptativa(
          larguraMinimaItem: 220,
          maxColunas: 4,
          children: [
            _metric(
              'Análises solicitadas hoje (UTC)',
              'analysis_requests_today',
            ),
            _metric(
              'Gerações solicitadas hoje (UTC)',
              'practice_requests_today',
            ),
            _metric('Resultados de IA gravados hoje', 'analyses_today'),
            _metric('Execuções em falha · últimas 24h', 'failures_24h'),
            _metric('Execuções com limite da API · 24h', 'rate_limited_24h'),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _snapshot == null
              ? 'Monitoramento global ainda não ativado no servidor.'
              : 'Consumo baseado nas reservas diárias do aplicativo; resultados são diagnósticos gravados. As falhas mostram o último estado de cada execução, não todas as chamadas HTTP.',
        ),
        const SizedBox(height: 8),
        Text(
          _snapshot?['last_analysis_at'] == null
              ? 'API de IA · ainda não há resultado gravado que confirme uma análise concluída.'
              : 'Último resultado de IA: ${_date(_snapshot!['last_analysis_at'])} · Modelo: ${_snapshot!['last_model'] ?? 'não informado'}',
        ),
        const SizedBox(height: 8),
        const Text(
          'Plano gratuito confirmado pelos prints do AI Studio em 30/09/2026. Cada modelo tem sua própria cota; solicitações internas do aplicativo podem gerar mais de uma chamada à API por repetição ou troca de modelo.',
        ),
        const SizedBox(height: 12),
        GradeAdaptativa(
          larguraMinimaItem: 240,
          maxColunas: 2,
          children: [
            for (final model in GeminiFreePlan.models) _modelQuota(model),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _apiSnapshot == null
              ? 'Consumo por modelo: aguardando ativação da telemetria das chamadas ao Gemini.'
              : 'Chamadas registradas pelo aplicativo desde ${_apiSnapshot!['observed_since'] == null ? 'a ativação (aguardando a primeira chamada)' : _date(_apiSnapshot!['observed_since'])}. Uso e saldo referem-se somente às chamadas registradas pelo aplicativo. Chamadas anteriores e feitas por outras ferramentas não estão incluídas.',
        ),
        const SizedBox(height: 12),
        if (_apiSnapshot != null) ..._providerMetrics(),
        const Text(
          'Os máximos históricos dos prints não são usados como consumo atual. As cotas diárias da API reiniciam à meia-noite no horário do Pacífico. Consulte o AI Studio para o saldo oficial do projeto.',
        ),
        const SizedBox(height: 24),
        const Text(
          'Armazenamento e cotas',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: MistakeMapDesign.primary,
          ),
        ),
        const SizedBox(height: 12),
        GradeAdaptativa(
          larguraMinimaItem: 220,
          maxColunas: 3,
          children: [
            _quota('R2 · operações Classe A no mês', 'r2_class_a', 1000000),
            _quota('R2 · operações Classe B no mês', 'r2_class_b', 10000000),
            _quota(
              'R2 · reserva estimada (GiB)',
              'r2_storage_estimate',
              10,
              bytes: true,
            ),
            _quota(
              'Supabase Storage · ocupação (GiB)',
              'storage_bytes',
              1,
              bytes: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'R2: franquia de 10 GB-mês, 1 milhão de operações A e 10 milhões B no armazenamento Standard. A reserva de bytes do aplicativo não é a medição de GB-mês da cobrança. O código bloqueia novas reservas R2 em 95% e uploads Supabase em 980 MB. Limites não garantem ausência de cobrança em contas com outros serviços ou buckets.',
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _metric(String label, String key) =>
      _card(label, _snapshot?[key]?.toString() ?? '—');
  Widget _modelQuota(String model) {
    final id = model.toLowerCase().replaceAll(' ', '-');
    final rows = _apiSnapshot?['models'];
    final matches = rows is List
        ? rows.whereType<Map>().where((row) => row['model'] == id)
        : <Map>[];
    final row = matches.isEmpty ? null : matches.first;
    return ModelQuotaCard(
      model: model,
      telemetryAvailable: _apiSnapshot != null,
      usage: row,
    );
  }

  List<Widget> _providerMetrics() {
    final rows = _apiSnapshot?['models'];
    if (rows is! List || rows.isEmpty) {
      return [
        const Text('Telemetria ativa · aguardando a primeira chamada à API.'),
        const SizedBox(height: 12),
      ];
    }
    return [
      for (final row in rows.whereType<Map>()) ...[
        Text(
          'Operação · ${row['model']?.toString() ?? 'Modelo não informado'}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        GradeAdaptativa(
          larguraMinimaItem: 220,
          maxColunas: 3,
          children: [
            if (![
              'gemini-3.8-flash',
              'gemini-3.6-flash',
            ].contains(row['model'])) ...[
              _card(
                'Requisições · último minuto',
                _providerCount(row, 'rpm', GeminiFreePlan.requestsPerMinute),
              ),
              _card(
                'Tokens de entrada · último minuto',
                '${_providerCount(row, 'tpm', GeminiFreePlan.inputTokensPerMinute)}${(row['unknown_tokens'] as num? ?? 0) > 0 ? '\nContagem parcial' : ''}',
              ),
              _card(
                'Requisições · dia do Pacífico',
                _providerCount(row, 'rpd', GeminiFreePlan.requestsPerDay),
              ),
            ],
            _card('Falhas nas chamadas · 24h', '${row['failures_24h'] ?? '—'}'),
            _card(
              'Limites da API (429) · 24h',
              '${row['throttled_24h'] ?? '—'}',
            ),
            _card(
              'Duração mediana · 24h',
              row['median_ms'] is num
                  ? '${(row['median_ms'] as num).round()} ms'
                  : '—',
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    ];
  }

  Widget _quota(String label, String key, num limit, {bool bytes = false}) {
    final raw = _snapshot?[key];
    final value = raw is num
        ? (bytes ? raw / (1024 * 1024 * 1024) : raw)
        : null;
    return _card(
      label,
      value == null
          ? '— / ${bytes ? '$limit GiB' : _number(limit)}'
          : '${bytes ? _bytes(raw as num) : _number(value)} / ${bytes ? '$limit GiB' : _number(limit)}',
      progress: value == null
          ? null
          : (value / limit).clamp(0.0, 1.0).toDouble(),
    );
  }

  String _providerCount(Map row, String key, int limit) {
    final confirmed = [
      'gemini-3.8-flash',
      'gemini-3.6-flash',
    ].contains(row['model']);
    return '${row[key] is num ? _number(row[key] as num) : '—'} / ${confirmed ? _number(limit) : 'limite não confirmado'}';
  }

  String _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return 'horário indisponível';
    final local = parsed.toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} às ${two(local.hour)}:${two(local.minute)}';
  }

  String _number(num value) => value.round().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]}.',
  );
  String _bytes(num value) {
    if (value < 1024) return '${value.round()} B';
    if (value < 1024 * 1024) {
      return '${(value / 1024).toStringAsFixed(1).replaceAll('.', ',')} KiB';
    }
    if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MiB';
    }
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2).replaceAll('.', ',')} GiB';
  }

  Widget _card(String label, String value, {double? progress}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: MistakeMapDesign.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: MistakeMapDesign.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: MistakeMapDesign.content,
          ),
        ),
        if (progress != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ProgressBar(value: progress * 100),
          ),
        ],
      ],
    ),
  );
}

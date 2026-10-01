import 'package:fluent_ui/fluent_ui.dart';

import '../theme/design_tokens.dart';
import 'free_plan.dart';

/// Quotas are compared with calls observed by the app, not project-wide billing.
class ModelQuotaCard extends StatelessWidget {
  const ModelQuotaCard({
    super.key,
    required this.model,
    required this.telemetryAvailable,
    this.usage,
  });

  final String model;
  final bool telemetryAvailable;
  final Map? usage;

  num? _used(String key) {
    if (!telemetryAvailable) return null;
    if (usage == null) return 0;
    final value = usage![key];
    return value is num && value >= 0 ? value : null;
  }

  static String _number(num value) => value.round().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]}.',
  );

  @override
  Widget build(BuildContext context) {
    final partial = (usage?['unknown_tokens'] as num? ?? 0) > 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFCFDFE), Color(0xFFF1F6FB)],
        ),
        borderRadius: BorderRadius.circular(MistakeMapDesign.radius),
        border: Border.all(color: MistakeMapDesign.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08142A4A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5EEF8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  WindowsIcons.lightbulb,
                  size: 18,
                  color: MistakeMapDesign.primary,
                ),
              ),
              Text(
                model,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: MistakeMapDesign.navy,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5EEF8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Plano gratuito',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: MistakeMapDesign.content,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            telemetryAvailable
                ? 'Consumo registrado pelo aplicativo'
                : 'Aguardando dados de consumo',
            style: const TextStyle(
              fontSize: 12,
              color: MistakeMapDesign.content,
            ),
          ),
          const SizedBox(height: 20),
          _quotaRow(
            'Requisições por minuto',
            'rpm',
            GeminiFreePlan.requestsPerMinute,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(),
          ),
          _quotaRow(
            'Tokens de entrada por minuto',
            'tpm',
            GeminiFreePlan.inputTokensPerMinute,
            partial: partial,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(),
          ),
          _quotaRow(
            'Requisições por dia',
            'rpd',
            GeminiFreePlan.requestsPerDay,
          ),
        ],
      ),
    );
  }

  Widget _quotaRow(
    String label,
    String key,
    int limit, {
    bool partial = false,
  }) {
    final used = _used(key);
    final ratio = used == null ? null : used / limit;
    final remaining = used == null ? null : (limit - used).clamp(0, limit);
    final color = partial || ratio == null
        ? MistakeMapDesign.content
        : ratio >= 1
        ? const Color(0xFFB42318)
        : ratio >= 0.8
        ? const Color(0xFF8A4B08)
        : MistakeMapDesign.primary;
    final percent = ratio == null
        ? 'Uso indisponível'
        : '${(ratio * 100).toStringAsFixed(used == 0 || ratio >= 0.01 ? 0 : 1).replaceAll('.', ',')}% da cota${partial ? ' · parcial' : ''}';
    final balance = used == null || partial
        ? 'Saldo indisponível'
        : '${_number(remaining!)} restantes';
    return Semantics(
      label:
          '$label. ${used == null ? 'Uso indisponível' : '${_number(used)} usados'}. Limite ${_number(limit)}. $balance${partial ? '. Contagem parcial' : ''}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: MistakeMapDesign.content,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  used == null ? '—' : _number(used),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  '/ ${_number(limit)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: MistakeMapDesign.content,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 6,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: MistakeMapDesign.border,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.centerLeft,
              child: ratio == null
                  ? null
                  : FractionallySizedBox(
                      widthFactor: ratio.clamp(0, 1).toDouble(),
                      heightFactor: 1,
                      child: ColoredBox(color: color),
                    ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(percent, style: TextStyle(fontSize: 12, color: color)),
                Text(
                  balance,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: MistakeMapDesign.content,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

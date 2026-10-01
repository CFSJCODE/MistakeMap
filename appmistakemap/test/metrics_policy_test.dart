import 'package:flutter_test/flutter_test.dart';
import 'package:appmistakemap/admin/metrics_policy.dart';

void main() {
  final now = DateTime.utc(2026, 9, 30, 12);
  test(
    'mobile and unknown enforce one hour including failed read attempts',
    () {
      for (final network in [NetworkKind.mobile, NetworkKind.unknown]) {
        expect(MetricsPolicy.live(network), false);
        expect(MetricsPolicy.due(network, null, now), true);
        expect(
          MetricsPolicy.due(network, now, now.add(const Duration(minutes: 59))),
          false,
        );
        expect(
          MetricsPolicy.due(network, now, now.add(const Duration(hours: 1))),
          true,
        );
      }
    },
  );
  test('only Wi-Fi permits live subscriptions, offline never reads', () {
    expect(MetricsPolicy.live(NetworkKind.wifi), true);
    expect(MetricsPolicy.due(NetworkKind.offline, null, now), false);
    expect(MetricsPolicy.live(NetworkKind.offline), false);
  });
}

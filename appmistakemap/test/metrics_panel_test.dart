import 'package:appmistakemap/admin/metrics_panel.dart';
import 'package:appmistakemap/admin/metrics_policy.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  setUpAll(() {
    client = SupabaseClient(
      'https://metrics.invalid',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => client.dispose());
  testWidgets('mobile waits an hour and pauses while the panel is hidden', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 9, 30, 12);
    var reads = 0;
    var active = true;
    Widget panel() => FluentApp(
      home: SingleChildScrollView(
        child: AdminMetricsPanel(
          client: client,
          active: active,
          network: () => NetworkKind.mobile,
          now: () => now,
          loadSnapshot: () async {
            reads++;
            return {
              'scope': 'global',
              'profiles': 2,
              'exercises': 4,
              'attempts': 4,
              'processing': 0,
            };
          },
        ),
      ),
    );
    await tester.pumpWidget(panel());
    await tester.pumpAndSettle();
    expect(reads, 1);
    now = now.add(const Duration(minutes: 59));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(reads, 1);
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(reads, 2);
    active = false;
    await tester.pumpWidget(panel());
    now = now.add(const Duration(hours: 2));
    await tester.pump(const Duration(seconds: 10));
    expect(reads, 2);
    active = true;
    await tester.pumpWidget(panel());
    await tester.pumpAndSettle();
    expect(reads, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

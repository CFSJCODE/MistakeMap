// Prepared adapter. Requires connectivity_plus in pubspec.yaml/pubspec.lock.
// Copy into lib/admin and enable its conditional export only after the user
// extends the Reversa allowlist for the dependency files.
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'metrics_policy.dart';

NetworkKind _kind = NetworkKind.unknown;
StreamSubscription<List<ConnectivityResult>>? _subscription;
final _changes = StreamController<NetworkKind>.broadcast();
Stream<NetworkKind> get networkChanges => _changes.stream;
NetworkKind currentNetwork() => _kind;
NetworkKind classifyNetwork(List<ConnectivityResult> results) {
  // Ambiguous mixed transports use the slower refresh policy.
  if (results.contains(ConnectivityResult.mobile)) return NetworkKind.mobile;
  if (results.contains(ConnectivityResult.wifi)) return NetworkKind.wifi;
  if (results.length == 1 && results.single == ConnectivityResult.none) return NetworkKind.offline;
  return NetworkKind.unknown;
}
void _update(List<ConnectivityResult> results) {
  final next = classifyNetwork(results);
  if (next == _kind) return;
  _kind = next;
  _changes.add(next);
}
Future<void> initializeNetwork() async {
  if (_subscription != null) return;
  final source = Connectivity();
  _subscription = source.onConnectivityChanged.listen(_update,
    onError: (_) { _kind = NetworkKind.unknown; _changes.add(_kind); });
  try { _update(await source.checkConnectivity()); }
  catch (_) { _kind = NetworkKind.unknown; }
}

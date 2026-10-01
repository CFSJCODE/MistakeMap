enum NetworkKind { wifi, mobile, offline, unknown }

/// Unknown transport never enables high-frequency reads.
class MetricsPolicy {
  static const interval = Duration(hours: 1);
  static bool live(NetworkKind network) => network == NetworkKind.wifi;
  static bool due(NetworkKind network, DateTime? last, DateTime now) =>
      network != NetworkKind.offline &&
      (last == null || now.difference(last) >= interval);
}

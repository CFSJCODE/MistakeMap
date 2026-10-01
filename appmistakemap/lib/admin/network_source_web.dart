import 'dart:js_interop';

import 'metrics_policy.dart';

@JS('navigator')
external JSObject get _navigator;

extension type _Navigator(JSObject _) implements JSObject {
  external bool get onLine;
  external _Connection? get connection;
}

extension type _Connection(JSObject _) implements JSObject {
  external String? get type;
}

NetworkKind currentNetwork() {
  final navigator = _Navigator(_navigator);
  if (!navigator.onLine) return NetworkKind.offline;
  // effectiveType describes speed, not Wi-Fi versus cellular.
  return switch (navigator.connection?.type) {
    'wifi' => NetworkKind.wifi,
    'cellular' => NetworkKind.mobile,
    _ => NetworkKind.unknown,
  };
}

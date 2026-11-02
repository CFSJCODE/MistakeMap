import 'dart:js_interop';

import 'package:flutter/foundation.dart';

@JS('window.matchMedia')
external _MediaQueryList _matchMedia(String query);

extension type _MediaQueryList(JSObject _) implements JSObject {
  external bool get matches;
  external void addEventListener(String type, JSFunction listener);
}

// Pedidos do navegador que o MediaQuery do Flutter não traz: reduzir
// transparência (macOS, iOS, Windows) e contraste maior. Com qualquer um
// deles o vidro vira superfície sólida, como no alto contraste.
const _consultas = [
  '(prefers-reduced-transparency: reduce)',
  '(prefers-contrast: more)',
];

final _vidroReduzido = _observar();

ValueNotifier<bool> _observar() {
  final listas = <_MediaQueryList>[];
  try {
    for (final consulta in _consultas) {
      listas.add(_matchMedia(consulta));
    }
  } catch (_) {
    return ValueNotifier(false);
  }
  bool atual() => listas.any((lista) => lista.matches);
  final valor = ValueNotifier(atual());
  for (final lista in listas) {
    lista.addEventListener(
      'change',
      (JSAny _) {
        valor.value = atual();
      }.toJS,
    );
  }
  return valor;
}

/// Verdadeiro quando o navegador pede menos transparência ou mais contraste.
ValueListenable<bool> get vidroReduzidoNoSistema => _vidroReduzido;

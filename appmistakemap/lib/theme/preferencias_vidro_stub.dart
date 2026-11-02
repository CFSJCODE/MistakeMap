import 'package:flutter/foundation.dart';

/// Fora do navegador o Flutter não expõe "reduzir transparência" nem
/// "contraste maior"; o alto contraste do sistema chega pelo MediaQuery.
final ValueListenable<bool> vidroReduzidoNoSistema = ValueNotifier(false);

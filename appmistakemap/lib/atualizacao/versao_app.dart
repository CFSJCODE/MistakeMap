/// Versão nativa embutida neste binário (APK/EXE).
///
/// Precisa casar com `version:` do pubspec.yaml: o teste `atualizacao_test`
/// confere. Ao subir a versão para um release novo, mude os dois juntos.
/// Patches do Shorebird não mudam estes valores; eles só trocam o código Dart
/// da mesma versão nativa.
const versaoApp = '1.0.0';

/// Número do build (o `+N` do pubspec). É ele que decide se um release
/// publicado no GitHub é mais novo que o app instalado.
const buildApp = 1;

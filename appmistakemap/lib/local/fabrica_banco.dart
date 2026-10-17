// Escolhe a implementação do SQLite pela plataforma: sqflite nativo no
// Android/iOS/macOS, FFI no Windows/Linux e WebAssembly no navegador.
export 'fabrica_banco_io.dart'
    if (dart.library.js_interop) 'fabrica_banco_web.dart';

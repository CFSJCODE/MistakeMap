import 'dart:io' show Directory, Platform;

import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool get _desktop => Platform.isWindows || Platform.isLinux;

DatabaseFactory fabricaDoBanco() {
  if (_desktop) {
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }
  return sqflite.databaseFactory;
}

Future<String> caminhoDoBanco(DatabaseFactory fabrica, String arquivo) async {
  if (!_desktop) return join(await fabrica.getDatabasesPath(), arquivo);
  // No desktop a pasta padrão do FFI é relativa ao diretório atual; os dados
  // do usuário ficam em %APPDATA% (Windows) ou ~/.local/share (Linux).
  final env = Platform.environment;
  final base = Platform.isWindows
      ? env['APPDATA']
      : env['XDG_DATA_HOME'] ??
            (env['HOME'] == null
                ? null
                : join(env['HOME']!, '.local', 'share'));
  if (base == null) return join(await fabrica.getDatabasesPath(), arquivo);
  final pasta = Directory(join(base, 'MistakeMap'));
  await pasta.create(recursive: true);
  return join(pasta.path, arquivo);
}

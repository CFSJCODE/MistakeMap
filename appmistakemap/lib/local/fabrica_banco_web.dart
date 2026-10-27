import 'package:sqflite/sqflite.dart' show DatabaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

// Usa web/sqlite3.wasm e web/sqflite_sw.js; o banco fica no IndexedDB.
DatabaseFactory fabricaDoBanco() => databaseFactoryFfiWeb;

Future<String> caminhoDoBanco(DatabaseFactory fabrica, String arquivo) async =>
    arquivo;

bool executandoTestes() => false;

import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart';

Future<void> initDatabase() async {
  // Use the web factory - backed by IndexedDB via sqlite3.wasm
  // Must be called before any openDatabase() call
  databaseFactory = databaseFactoryFfiWeb;
}

import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart';

void setupSqfliteFactory() {
  databaseFactory = createDatabaseFactoryFfiWeb(
    options: SqfliteFfiWebOptions(
      sqlite3WasmUri: Uri.parse('sqlite3.wasm'),
      sharedWorkerUri: Uri.parse('sqflite_sw.js'),
    ),
  );
}

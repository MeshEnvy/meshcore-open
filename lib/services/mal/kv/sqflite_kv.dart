import '../../../utils/platform_info.dart';
import 'kv_store.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:path/path.dart' as p;

/// SQLite-backed implementation of the high-performance MeshKvStore.
///
/// This provider uses `sqflite` on mobile and `sqflite_common_ffi` on desktop,
/// along with FFI web adapters (if compiling for web). It stores all keys and
/// values in a single table with a compound primary key on `(scope, key)`.
class SqfliteKvStore implements MeshKvStore {
  Database? _db;

  /// Private constructor
  SqfliteKvStore._();

  /// Singleton instance
  static final SqfliteKvStore _instance = SqfliteKvStore._();

  /// Gets the singleton instance
  static SqfliteKvStore get instance => _instance;

  @override
  Future<void> init() async {
    if (_db != null) return;

    if (PlatformInfo.isWeb) {
      // For pure Web, we would typically inject the Web FFI factory here.
      // But we will use the dynamic factory approach for cross-platform support.
      // If we are strictly on web, `sqflite_common_ffi_web` export is required.
      // We assume the Flutter caller has invoked `databaseFactory = databaseFactoryFfiWeb`
      // before this point if running on the web, to keep this clean.
    } else if (PlatformInfo.isDesktop) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'mesh_kv_store.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE kv_store ('
          '  scope TEXT NOT NULL,'
          '  key TEXT NOT NULL,'
          '  value TEXT,'
          '  PRIMARY KEY (scope, key)'
          ')',
        );
        // Create an index on scope to make prefix/scans highly efficient
        await db.execute('CREATE INDEX idx_kv_scope ON kv_store (scope)');
      },
    );
  }

  Future<Database> get _database async {
    if (_db == null) await init();
    return _db!;
  }

  @override
  Future<String?> get(String key, String scope) async {
    final db = await _database;

    final maps = await db.query(
      'kv_store',
      columns: ['value'],
      where: 'scope = ? AND key = ?',
      whereArgs: [scope, key],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return maps.first['value'] as String?;
    }
    return null;
  }

  @override
  Future<void> set(String key, String value, String scope) async {
    final db = await _database;

    await db.insert('kv_store', {
      'scope': scope,
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(String key, String scope) async {
    final db = await _database;

    await db.delete(
      'kv_store',
      where: 'scope = ? AND key = ?',
      whereArgs: [scope, key],
    );
  }

  @override
  Future<List<String>> getKeys(String scope) async {
    final db = await _database;
    final maps = await db.query(
      'kv_store',
      columns: ['key'],
      where: 'scope = ?',
      whereArgs: [scope],
    );

    return maps.map((e) => e['key'] as String).toList();
  }
}

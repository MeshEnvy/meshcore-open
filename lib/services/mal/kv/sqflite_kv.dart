import '../../../utils/platform_info.dart';
import 'kv_store.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// SQLite-backed implementation of the high-performance MeshKvStore.
///
/// This provider handles per-node storage by creating a separate database file
/// for each `nodeId` (scope) within the node's dedicated directory.
class SqfliteKvStore implements MeshKvStore {
  Database? _db;
  bool _initialized = false;

  /// Private constructor
  SqfliteKvStore._();

  /// Singleton instance
  static final SqfliteKvStore _instance = SqfliteKvStore._();

  /// Gets the singleton instance
  static SqfliteKvStore get instance => _instance;

  @override
  Future<void> init() async {
    if (_initialized) return;

    if (PlatformInfo.isWeb) {
      // Factory should be set by the caller (e.g., in main.dart)
    } else if (PlatformInfo.isDesktop) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _initialized = true;
  }

  Future<Database> _getDatabase() async {
    if (!_initialized) await init();
    if (_db != null) return _db!;

    String path;
    if (PlatformInfo.isWeb) {
      path = 'mesh_kv_store.db';
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      path = p.join(docsDir.path, 'mesh_kv_store.db');
    }

    final db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE kv_store ('
          '  key TEXT PRIMARY KEY,'
          '  value TEXT'
          ')',
        );
      },
    );
    _db = db;
    return db;
  }

  @override
  Future<String?> get(String key) async {
    final db = await _getDatabase();

    final maps = await db.query(
      'kv_store',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return maps.first['value'] as String?;
    }
    return null;
  }

  @override
  Future<void> set(String key, String value) async {
    final db = await _getDatabase();

    await db.insert('kv_store', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(String key) async {
    final db = await _getDatabase();

    await db.delete('kv_store', where: 'key = ?', whereArgs: [key]);
  }

  @override
  Future<List<String>> getKeys() async {
    final db = await _getDatabase();
    final maps = await db.query('kv_store', columns: ['key']);

    return maps.map((e) => e['key'] as String).toList();
  }
}

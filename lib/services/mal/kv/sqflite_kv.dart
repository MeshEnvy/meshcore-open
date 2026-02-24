import '../../../utils/platform_info.dart';
import 'kv_store.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'sqflite_factory_stub.dart'
    if (dart.library.io) 'sqflite_factory_io.dart'
    if (dart.library.html) 'sqflite_factory_web.dart';

/// SQLite-backed implementation of the high-performance MeshKvStore.
///
/// This provider handles per-node storage by creating a separate database file
/// for each `nodeId` (scope) within the node's dedicated directory.
class SqfliteKvStore implements MeshKvStore {
  Database? _db;
  bool _initialized = false;
  Future<void>? _initFuture;

  /// Private constructor
  SqfliteKvStore._();

  /// Singleton instance
  static final SqfliteKvStore _instance = SqfliteKvStore._();

  /// Gets the singleton instance
  static SqfliteKvStore get instance => _instance;

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initFuture ??= _initInternal();
    return _initFuture!;
  }

  Future<void> _initInternal() async {
    setupSqfliteFactory();
    await _getDatabase();
    _initialized = true;
  }

  Future<Database> _getDatabase() async {
    if (_db != null) return _db!;

    String path;
    if (PlatformInfo.isWeb) {
      path = 'mesh_kv_store.db';
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      path = p.join(docsDir.path, 'mesh_kv_store.db');
    }

    try {
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
      ).timeout(const Duration(seconds: 5));
      _db = db;
      return db;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<String?> get(String key) async {
    await init();
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
    await init();
    final db = await _getDatabase();
    await db.insert('kv_store', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(String key) async {
    await init();
    final db = await _getDatabase();
    await db.delete('kv_store', where: 'key = ?', whereArgs: [key]);
  }

  @override
  Future<List<String>> getKeys() async {
    await init();
    final db = await _getDatabase();
    final maps = await db.query('kv_store', columns: ['key']);
    return maps.map((e) => e['key'] as String).toList();
  }
}

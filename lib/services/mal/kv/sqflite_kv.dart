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
  String? _overridePath;

  /// Private constructor
  SqfliteKvStore._();

  /// Singleton instance
  static final SqfliteKvStore _instance = SqfliteKvStore._();

  /// Gets the singleton instance
  static SqfliteKvStore get instance => _instance;

  /// Sets an override path for the database. Useful for testing.
  void overrideDatabasePath(String? path) {
    _overridePath = path;
    _db = null;
    _initialized = false;
    _initFuture = null;
  }

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
    if (_overridePath != null) {
      path = _overridePath!;
    } else if (PlatformInfo.isWeb) {
      path = 'mesh_kv_store.db';
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      path = p.join(docsDir.path, 'mesh_kv_store.db');
    }

    try {
      final db = await openDatabase(
        path,
        version: 3,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 3) {
            await db.execute('DROP TABLE IF EXISTS kv_store');
            await db.execute(
              'CREATE TABLE kv_store ('
              '  key TEXT,'
              '  scope TEXT,'
              '  value TEXT,'
              '  PRIMARY KEY (key, scope)'
              ')',
            );
          }
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE kv_store ('
            '  key TEXT,'
            '  scope TEXT,'
            '  value TEXT,'
            '  PRIMARY KEY (key, scope)'
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
  Future<String?> get(String key, {String? scope}) async {
    await init();
    final db = await _getDatabase();
    final maps = await db.query(
      'kv_store',
      columns: ['value'],
      where: 'key = ? AND scope = ?',
      whereArgs: [key, scope ?? 'global'],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return maps.first['value'] as String?;
    }
    return null;
  }

  @override
  Future<void> set(String key, String value, {String? scope}) async {
    await init();
    final db = await _getDatabase();
    await db.insert('kv_store', {
      'key': key,
      'scope': scope ?? 'global',
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(String key, {String? scope}) async {
    await init();
    final db = await _getDatabase();
    await db.delete(
      'kv_store',
      where: 'key = ? AND scope = ?',
      whereArgs: [key, scope ?? 'global'],
    );
  }

  @override
  Future<List<String>> getKeys({String? scope}) async {
    await init();
    final db = await _getDatabase();
    final maps = await db.query(
      'kv_store',
      columns: ['key'],
      where: 'scope = ?',
      whereArgs: [scope ?? 'global'],
    );
    return maps.map((e) => e['key'] as String).toList();
  }

  @override
  Future<Map<String, String>> getValues({String? scope}) async {
    await init();
    final db = await _getDatabase();
    final maps = await db.query(
      'kv_store',
      columns: ['key', 'value'],
      where: 'scope = ?',
      whereArgs: [scope ?? 'global'],
    );
    return {for (final m in maps) m['key'] as String: m['value'] as String};
  }
}

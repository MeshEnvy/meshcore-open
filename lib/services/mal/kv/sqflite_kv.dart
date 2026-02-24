import 'dart:io';
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
  final Map<String, Database> _databases = {};
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

  Future<Database> _getDatabase(String scope) async {
    if (!_initialized) await init();
    if (_databases.containsKey(scope)) return _databases[scope]!;

    String path;
    if (PlatformInfo.isWeb) {
      // On Web, we use the same logical structure (nodeId/filename)
      // which acts as a unique IndexedDB database name.
      path = p.join(scope, 'mesh_kv_store.db');
    } else {
      // On Native, we use the node-specific directory requested by the user:
      // Documents/<nodeId>/mesh_kv_store.db
      final docsDir = await getApplicationDocumentsDirectory();
      final nodeRoot = p.join(docsDir.path, scope);
      final dir = Directory(nodeRoot);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      path = p.join(nodeRoot, 'mesh_kv_store.db');
    }

    final db = await openDatabase(
      path,
      version:
          2, // Bump version if we want to force schema update, but here it's a new file
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE kv_store ('
          '  key TEXT PRIMARY KEY,'
          '  value TEXT'
          ')',
        );
      },
    );
    _databases[scope] = db;
    return db;
  }

  @override
  Future<String?> get(String key, String scope) async {
    final db = await _getDatabase(scope);

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
  Future<void> set(String key, String value, String scope) async {
    final db = await _getDatabase(scope);

    await db.insert('kv_store', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(String key, String scope) async {
    final db = await _getDatabase(scope);

    await db.delete('kv_store', where: 'key = ?', whereArgs: [key]);
  }

  @override
  Future<List<String>> getKeys(String scope) async {
    final db = await _getDatabase(scope);
    final maps = await db.query('kv_store', columns: ['key']);

    return maps.map((e) => e['key'] as String).toList();
  }
}

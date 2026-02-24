import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'package:path/path.dart' as p;

import 'vfs.dart';

/// Provides the NativeVfs implementation. Throws an error if called on web.
VirtualFileSystem getNativeVfs() {
  throw UnsupportedError('getNativeVfs is not supported on the web.');
}

/// Provides the WebVfs implementation.
VirtualFileSystem getWebVfs() => WebVfs();

/// A web implementation of the VirtualFileSystem using IndexedDB.
class WebVfs extends VirtualFileSystem {
  late String _drivePath;
  static const String _dbName = 'meshcore_vfs';
  static const int _dbVersion = 1;
  static const String _storeName = 'files';

  web.IDBDatabase? _db;

  Future<web.IDBDatabase> _getDb() async {
    if (_db != null) return _db!;

    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_dbName, _dbVersion);

    request.onupgradeneeded = (web.IDBVersionChangeEvent event) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }.toJS;

    request.onsuccess = (web.Event event) {
      _db = request.result as web.IDBDatabase;
      completer.complete(_db);
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError(
        'Failed to open IndexedDB: ${request.error?.name}',
      );
    }.toJS;

    return completer.future;
  }

  @override
  Future<String> init(String nodeId) async {
    _drivePath = '/$nodeId/drive';
    // Ensure root directory exists
    if (!await exists(_drivePath)) {
      await createDir(_drivePath);
    }
    return _drivePath;
  }

  Future<dynamic> _getRecord(String path) async {
    final db = await _getDb();
    final tx = db.transaction(_storeName.toJS, 'readonly');
    final store = tx.objectStore(_storeName);

    final completer = Completer<dynamic>();
    final request = store.get(path.toJS);

    request.onsuccess = (web.Event event) {
      completer.complete(request.result);
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to get record: ${request.error?.name}');
    }.toJS;

    return completer.future;
  }

  Future<void> _putRecord(String path, Object? data) async {
    final db = await _getDb();
    final tx = db.transaction(_storeName.toJS, 'readwrite');
    final store = tx.objectStore(_storeName);

    final completer = Completer<void>();
    final request = store.put(data.jsify()!, path.toJS);

    request.onsuccess = (web.Event event) {
      completer.complete();
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to put record: ${request.error?.name}');
    }.toJS;

    return completer.future;
  }

  Future<void> _deleteRecord(String path) async {
    final db = await _getDb();
    final tx = db.transaction(_storeName.toJS, 'readwrite');
    final store = tx.objectStore(_storeName);

    final completer = Completer<void>();
    final request = store.delete(path.toJS);

    request.onsuccess = (web.Event event) {
      completer.complete();
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError(
        'Failed to delete record: ${request.error?.name}',
      );
    }.toJS;

    return completer.future;
  }

  @override
  Future<bool> exists(String path) async {
    final normalizedPath = p.normalize(path);
    final record = await _getRecord(normalizedPath);
    return record != null;
  }

  Future<void> _ensureParentDirExists(String path) async {
    final parentPath = p.dirname(path);
    if (parentPath == '/' || parentPath == '.') return;

    if (!await exists(parentPath)) {
      await createDir(parentPath);
    }
  }

  @override
  Future<void> createDir(String path) async {
    final normalizedPath = p.normalize(path);
    await _ensureParentDirExists(normalizedPath);
    // Store directories as an empty object/js structure with a type marker
    await _putRecord(normalizedPath, {'type': 'dir'});
  }

  @override
  Future<void> createFile(String path) async {
    final normalizedPath = p.normalize(path);
    if (await exists(normalizedPath)) return;

    await _ensureParentDirExists(normalizedPath);
    // Store files as map containing byte array data
    await _putRecord(normalizedPath, {
      'type': 'file',
      'data': Uint8List(0).toJS,
    });
  }

  @override
  Future<void> writeAsBytes(String path, Uint8List bytes) async {
    final normalizedPath = p.normalize(path);
    await _ensureParentDirExists(normalizedPath);
    await _putRecord(normalizedPath, {'type': 'file', 'data': bytes.toJS});
  }

  @override
  Future<Uint8List> readAsBytes(String path) async {
    final normalizedPath = p.normalize(path);
    final record = await _getRecord(normalizedPath);

    if (record == null) {
      throw FileSystemException('File not found', path);
    }

    // JS interop logic to extract byte buffer
    final jsObj = record as JSObject;
    final typeStr = jsObj.getProperty<JSString?>('type'.toJS);
    if (typeStr?.toDart != 'file') {
      throw FileSystemException('Path is a directory, not a file', path);
    }

    final data = jsObj.getProperty<JSUint8Array?>('data'.toJS);
    return data?.toDart ?? Uint8List(0);
  }

  @override
  Future<void> delete(String path) async {
    final normalizedPath = p.normalize(path);
    final record = await _getRecord(normalizedPath);
    if (record == null) return;

    final jsObj = record as JSObject;
    final typeStr = jsObj.getProperty<JSString?>('type'.toJS);

    if (typeStr?.toDart == 'dir') {
      // Must delete recursively
      final allKeys = await _getAllKeys();
      final prefix = '$normalizedPath/';
      for (final key in allKeys) {
        if (key.startsWith(prefix)) {
          await _deleteRecord(key);
        }
      }
    }

    await _deleteRecord(normalizedPath);
  }

  /// Helper to get all stored keys from IndexedDB
  Future<List<String>> _getAllKeys() async {
    final db = await _getDb();
    final tx = db.transaction(_storeName.toJS, 'readonly');
    final store = tx.objectStore(_storeName);

    final completer = Completer<List<String>>();
    final request = store.getAllKeys();

    request.onsuccess = (web.Event event) {
      final resultKeys = request.result as JSArray;
      final keys = <String>[];
      for (var i = 0; i < resultKeys.length; i++) {
        final key = resultKeys[i] as JSString;
        keys.add(key.toDart);
      }
      completer.complete(keys);
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to get all keys: ${request.error?.name}');
    }.toJS;

    return completer.future;
  }

  @override
  Future<List<VfsNode>> list(String path) async {
    final normalizedPath = p.normalize(path);
    if (!await exists(normalizedPath)) return [];

    final allKeys = await _getAllKeys();
    final prefix = normalizedPath == '/' ? '/' : '$normalizedPath/';

    final children = <VfsNode>[];
    final addedPaths = <String>{};

    for (final key in allKeys) {
      if (key == normalizedPath) continue;

      if (key.startsWith(prefix)) {
        // Find immediate child
        final suffix = key.substring(prefix.length);
        final segments = suffix.split('/');

        // The first segment is an immediate child of our directory
        final childName = segments[0];
        final childPath = '$prefix$childName';

        if (!addedPaths.contains(childPath)) {
          addedPaths.add(childPath);
          final record = await _getRecord(childPath);
          final typeStr = (record as JSObject).getProperty<JSString?>(
            'type'.toJS,
          );

          children.add(
            VfsNode(
              path: childPath,
              isDir: typeStr?.toDart == 'dir',
              name: childName,
            ),
          );
        }
      }
    }

    return children;
  }
}

class FileSystemException implements Exception {
  final String message;
  final String path;
  FileSystemException(this.message, this.path);
  @override
  String toString() => "FileSystemException: $message ($path)";
}

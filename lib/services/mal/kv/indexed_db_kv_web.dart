import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'kv_store.dart';

/// IndexedDB-backed implementation of MeshKvStore for Web.
class IndexedDbKvStore implements MeshKvStore {
  static const String _dbName = 'mesh_kv_store';
  static const String _storeName = 'kv_store';
  static const int _version = 2;

  web.IDBDatabase? _db;
  bool _initialized = false;
  Future<void>? _initFuture;

  IndexedDbKvStore._();
  static final IndexedDbKvStore _instance = IndexedDbKvStore._();
  static IndexedDbKvStore get instance => _instance;

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initFuture ??= _initInternal();
    return _initFuture!;
  }

  Future<void> _initInternal() async {
    final completer = Completer<void>();
    final request = web.window.indexedDB.open(_dbName, _version);

    request.onupgradeneeded = (web.IDBVersionChangeEvent e) {
      final db = request.result as web.IDBDatabase;
      if (db.objectStoreNames.contains(_storeName)) {
        db.deleteObjectStore(_storeName);
      }
      final store = db.createObjectStore(
        _storeName,
        web.IDBObjectStoreParameters(keyPath: ['key'.toJS, 'scope'.toJS].toJS),
      );
      store.createIndex('scope', 'scope'.toJS);
    }.toJS;

    request.onsuccess = (web.Event e) {
      _db = request.result as web.IDBDatabase;
      _initialized = true;
      completer.complete();
    }.toJS;

    request.onerror = (web.Event e) {
      completer.completeError('Failed to open IndexedDB: ${request.error}');
    }.toJS;

    return completer.future;
  }

  Future<web.IDBObjectStore> _getStore([String mode = 'readonly']) async {
    await init();
    if (_db == null) throw StateError('Database not initialized');
    final transaction = _db!.transaction([(_storeName).toJS].toJS, mode);
    return transaction.objectStore(_storeName);
  }

  @override
  Future<String?> get(String key, {String? scope}) async {
    final store = await _getStore();
    final completer = Completer<String?>();
    final compositeKey = [key.toJS, (scope ?? 'global').toJS].toJS;
    final request = store.get(compositeKey);

    request.onsuccess = (web.Event e) {
      final result = request.result;
      if (result == null || result.isUndefinedOrNull) {
        completer.complete(null);
      } else {
        final map = result as JSObject;
        completer.complete((map.getProperty('value'.toJS) as JSString).toDart);
      }
    }.toJS;

    request.onerror = (web.Event e) {
      completer.completeError('Failed to get key $key: ${request.error}');
    }.toJS;

    return completer.future;
  }

  @override
  Future<void> set(String key, String value, {String? scope}) async {
    final store = await _getStore('readwrite');
    final completer = Completer<void>();
    final obj = JSObject();
    obj.setProperty('key'.toJS, key.toJS);
    obj.setProperty('scope'.toJS, (scope ?? 'global').toJS);
    obj.setProperty('value'.toJS, value.toJS);

    final request = store.put(obj);

    request.onsuccess = (web.Event e) {
      completer.complete();
    }.toJS;

    request.onerror = (web.Event e) {
      completer.completeError('Failed to set key $key: ${request.error}');
    }.toJS;

    return completer.future;
  }

  @override
  Future<void> delete(String key, {String? scope}) async {
    final store = await _getStore('readwrite');
    final completer = Completer<void>();
    final compositeKey = [key.toJS, (scope ?? 'global').toJS].toJS;
    final request = store.delete(compositeKey);

    request.onsuccess = (web.Event e) {
      completer.complete();
    }.toJS;

    request.onerror = (web.Event e) {
      completer.completeError('Failed to delete key $key: ${request.error}');
    }.toJS;

    return completer.future;
  }

  @override
  Future<List<String>> getKeys({String? scope}) async {
    final store = await _getStore();
    final completer = Completer<List<String>>();
    final index = store.index('scope');
    final request = index.getAllKeys((scope ?? 'global').toJS);

    request.onsuccess = (web.Event e) {
      final results = (request.result as JSArray).toDart;
      final keys = results.map((r) {
        final compositeKey = (r as JSArray).toDart;
        return (compositeKey[0] as JSString).toDart;
      }).toList();
      completer.complete(keys);
    }.toJS;

    request.onerror = (web.Event e) {
      completer.completeError('Failed to get keys: ${request.error}');
    }.toJS;

    return completer.future;
  }
}

MeshKvStore getIndexedDbKvStore() => IndexedDbKvStore.instance;

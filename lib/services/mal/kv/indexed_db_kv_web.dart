import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'kv_store.dart';

/// IndexedDB-backed implementation of MeshKvStore for Web.
class IndexedDbKvStore implements MeshKvStore {
  static const String _dbName = 'mesh_kv_store';
  static const String _storeName = 'kv_store';
  static const int _version = 1;

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
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
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
  Future<String?> get(String key) async {
    final store = await _getStore();
    final completer = Completer<String?>();
    final request = store.get(key.toJS);

    request.onsuccess = (web.Event e) {
      final result = request.result;
      if (result == null || result.isUndefinedOrNull) {
        completer.complete(null);
      } else {
        completer.complete((result as JSString).toDart);
      }
    }.toJS;

    request.onerror = (web.Event e) {
      completer.completeError('Failed to get key $key: ${request.error}');
    }.toJS;

    return completer.future;
  }

  @override
  Future<void> set(String key, String value) async {
    final store = await _getStore('readwrite');
    final completer = Completer<void>();
    final request = store.put(value.toJS, key.toJS);

    request.onsuccess = (web.Event e) {
      completer.complete();
    }.toJS;

    request.onerror = (web.Event e) {
      completer.completeError('Failed to set key $key: ${request.error}');
    }.toJS;

    return completer.future;
  }

  @override
  Future<void> delete(String key) async {
    final store = await _getStore('readwrite');
    final completer = Completer<void>();
    final request = store.delete(key.toJS);

    request.onsuccess = (web.Event e) {
      completer.complete();
    }.toJS;

    request.onerror = (web.Event e) {
      completer.completeError('Failed to delete key $key: ${request.error}');
    }.toJS;

    return completer.future;
  }

  @override
  Future<List<String>> getKeys() async {
    final store = await _getStore();
    final completer = Completer<List<String>>();
    final request = store.getAllKeys();

    request.onsuccess = (web.Event e) {
      final keys = (request.result as JSArray).toDart;
      completer.complete(keys.map((k) => (k as JSString).toDart).toList());
    }.toJS;

    request.onerror = (web.Event e) {
      completer.completeError('Failed to get keys: ${request.error}');
    }.toJS;

    return completer.future;
  }
}

MeshKvStore getIndexedDbKvStore() => IndexedDbKvStore.instance;

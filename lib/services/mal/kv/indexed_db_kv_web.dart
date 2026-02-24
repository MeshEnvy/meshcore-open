import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
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
    if (kDebugMode) print('[IndexedDbKvStore] Starting _initInternal...');
    final completer = Completer<void>();
    final request = web.window.indexedDB.open(_dbName, _version);

    request.onupgradeneeded = (web.IDBVersionChangeEvent e) {
      if (kDebugMode) print('[IndexedDbKvStore] onupgradeneeded...');
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
      if (kDebugMode) print('[IndexedDbKvStore] onsuccess.');
      _db = request.result as web.IDBDatabase;
      _initialized = true;
      completer.complete();
    }.toJS;

    request.onerror = (web.Event e) {
      if (kDebugMode) print('[IndexedDbKvStore] onerror: ${request.error}');
      completer.completeError('Failed to open IndexedDB: ${request.error}');
    }.toJS;

    return completer.future;
  }

  Future<web.IDBObjectStore> _getStore([String mode = 'readonly']) async {
    if (kDebugMode) print('[IndexedDbKvStore] _getStore(mode: $mode)...');
    await init();
    if (_db == null) {
      if (kDebugMode)
        print('[IndexedDbKvStore] _getStore: Database not initialized!');
      throw StateError('Database not initialized');
    }
    final transaction = _db!.transaction([(_storeName).toJS].toJS, mode);
    return transaction.objectStore(_storeName);
  }

  @override
  Future<String?> get(String key, {String? scope}) async {
    if (kDebugMode)
      print('[IndexedDbKvStore] get(key: $key, scope: $scope)...');
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
    if (kDebugMode)
      print('[IndexedDbKvStore] set(key: $key, scope: $scope)...');
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
    if (kDebugMode) print('[IndexedDbKvStore] getKeys(scope: $scope)...');
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

  @override
  Future<Map<String, String>> getValues({String? scope}) async {
    if (kDebugMode) print('[IndexedDbKvStore] getValues(scope: $scope)...');
    final store = await _getStore();
    final completer = Completer<Map<String, String>>();
    final index = store.index('scope');
    final request = index.getAll((scope ?? 'global').toJS);

    request.onsuccess = (web.Event e) {
      if (kDebugMode) print('[IndexedDbKvStore] getValues onsuccess starts...');
      try {
        final result = request.result;
        if (result == null || result.isUndefinedOrNull) {
          if (kDebugMode)
            print('[IndexedDbKvStore] getValues: result is null or undefined');
          completer.complete({});
          return;
        }

        final results = (result as JSArray).toDart;
        if (kDebugMode)
          print(
            '[IndexedDbKvStore] getValues found ${results.length} raw results',
          );

        final Map<String, String> map = {};
        for (var i = 0; i < results.length; i++) {
          final r = results[i];
          final obj = r as JSObject;
          final keyJs = obj.getProperty('key'.toJS);
          final valJs = obj.getProperty('value'.toJS);

          if (keyJs.isUndefinedOrNull || valJs.isUndefinedOrNull) {
            if (kDebugMode)
              print(
                '[IndexedDbKvStore] getValues: entry $i has null key or value',
              );
            continue;
          }

          final key = (keyJs as JSString).toDart;
          final value = (valJs as JSString).toDart;
          map[key] = value;
        }
        if (kDebugMode)
          print(
            '[IndexedDbKvStore] getValues returning map with ${map.length} entries',
          );
        completer.complete(map);
      } catch (err) {
        if (kDebugMode)
          print('[IndexedDbKvStore] getValues error during processing: $err');
        completer.completeError('Error processing getValues results: $err');
      }
    }.toJS;

    request.onerror = (web.Event e) {
      completer.completeError('Failed to get values: ${request.error}');
    }.toJS;

    return completer.future;
  }
}

MeshKvStore getIndexedDbKvStore() => IndexedDbKvStore.instance;

import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'vfs.dart';
import '../kv/kv_store.dart';

/// Provides the KvVfs implementation.
VirtualFileSystem getWebVfs(MeshKvStore kvStore) => KvVfs(kvStore);

/// Provides the NativeVfs implementation. Throws an error if called on web.
VirtualFileSystem getNativeVfs() {
  throw UnsupportedError('getNativeVfs is not supported on web platforms.');
}

/// A VirtualFileSystem implementation that uses `MeshKvStore` to simulate
/// a file system. This is primarily used as a fallback on the Web or in
/// highly restricted sandbox environments where `dart:io` cannot be used.
///
/// Note: To support binary data securely in the text-based KV store,
/// file contents are stored as Base64 encoded strings.
class KvVfs extends VirtualFileSystem {
  final MeshKvStore _kvStore;

  // The scope used in the KV store to isolate VFS data from ENV variables
  static const String _vfsScope = 'vfs';

  KvVfs(this._kvStore);

  String _toKvKey(String path) {
    // Normalize path to ensure consistent keys
    return p.normalize(path);
  }

  @override
  Future<String> init() async {
    // Since this is KV-backed, the "drive path" is conceptual.
    // We return a normalized conceptual root.
    return '/';
  }

  @override
  Future<bool> exists(String path) async {
    final key = _toKvKey(path);
    final val = await _kvStore.get(key, scope: _vfsScope);
    return val != null;
  }

  Future<void> _ensureParentDirExists(String path) async {
    final parent = p.dirname(path);
    if (parent == '.' || parent == '/') return;

    final existsParent = await exists(parent);
    if (!existsParent) {
      await createDir(parent);
    }
  }

  Map<String, dynamic> _decode(String val) {
    return json.decode(val) as Map<String, dynamic>;
  }

  String _encode(Map<String, dynamic> data) {
    return json.encode(data);
  }

  @override
  Future<void> createDir(String path) async {
    await _ensureParentDirExists(path);
    final key = _toKvKey(path);
    await _kvStore.set(
      key,
      _encode({'type': 'dir', 'mtime': DateTime.now().millisecondsSinceEpoch}),
      scope: _vfsScope,
    );
  }

  @override
  Future<void> createFile(String path) async {
    await _ensureParentDirExists(path);
    final key = _toKvKey(path);
    await _kvStore.set(
      key,
      _encode({
        'type': 'file',
        'encoding': 'utf8',
        'data': '',
        'size': 0,
        'mtime': DateTime.now().millisecondsSinceEpoch,
      }),
      scope: _vfsScope,
    );
  }

  @override
  Future<void> writeAsString(String path, String content) async {
    await _ensureParentDirExists(path);
    final key = _toKvKey(path);
    await _kvStore.set(
      key,
      _encode({
        'type': 'file',
        'encoding': 'utf8',
        'data': content,
        'size': utf8.encode(content).length,
        'mtime': DateTime.now().millisecondsSinceEpoch,
      }),
      scope: _vfsScope,
    );
  }

  @override
  Future<String> readAsString(String path) async {
    final key = _toKvKey(path);
    final val = await _kvStore.get(key, scope: _vfsScope);

    if (val == null) {
      throw FileSystemException('File not found', path);
    }

    final data = _decode(val);
    if (data['type'] == 'dir') {
      throw FileSystemException('Path is a directory, not a file', path);
    }

    if (data['encoding'] == 'utf8') {
      return data['data'] as String;
    } else {
      final bytes = base64.decode(data['data'] as String);
      return utf8.decode(bytes);
    }
  }

  @override
  Future<void> writeAsBytes(String path, Uint8List bytes) async {
    await _ensureParentDirExists(path);
    final key = _toKvKey(path);
    await _kvStore.set(
      key,
      _encode({
        'type': 'file',
        'encoding': 'base64',
        'data': base64.encode(bytes),
        'size': bytes.length,
        'mtime': DateTime.now().millisecondsSinceEpoch,
      }),
      scope: _vfsScope,
    );
  }

  @override
  Future<Uint8List> readAsBytes(String path) async {
    final key = _toKvKey(path);
    final val = await _kvStore.get(key, scope: _vfsScope);

    if (val == null) {
      throw FileSystemException('File not found', path);
    }

    final data = _decode(val);
    if (data['type'] == 'dir') {
      throw FileSystemException('Path is a directory, not a file', path);
    }

    if (data['encoding'] == 'base64') {
      return base64.decode(data['data'] as String);
    } else {
      return Uint8List.fromList(utf8.encode(data['data'] as String));
    }
  }

  @override
  Future<void> delete(String path) async {
    final key = _toKvKey(path);
    final val = await _kvStore.get(key, scope: _vfsScope);

    if (val == null) return;

    final data = _decode(val);
    if (data['type'] == 'dir') {
      final allKeys = await _kvStore.getKeys(scope: _vfsScope);
      final targetPrefix = (key == '/' || key == '')
          ? '/'
          : (key.endsWith('/') ? key : '$key/');

      for (final k in allKeys) {
        if (k.startsWith(targetPrefix)) {
          await _kvStore.delete(k, scope: _vfsScope);
        }
      }
    }

    await _kvStore.delete(key, scope: _vfsScope);
  }

  @override
  Future<List<VfsNode>> list(String path) async {
    final normalizedPath = p.normalize(path);
    final targetPrefix = normalizedPath == '/'
        ? ''
        : (normalizedPath.endsWith('/') ? normalizedPath : '$normalizedPath/');

    final allKeys = await _kvStore.getKeys(scope: _vfsScope);
    final Map<String, VfsNode> nodes = {};

    for (final key in allKeys) {
      if (key.startsWith(targetPrefix)) {
        final relativePath = key.substring(targetPrefix.length);
        if (relativePath.isEmpty) continue;

        final parts = p.split(relativePath);
        if (parts.isNotEmpty) {
          final childName = parts.first;
          final childFullPath = p.join(normalizedPath, childName);
          final childVal = await _kvStore.get(childFullPath, scope: _vfsScope);

          if (childVal != null && !nodes.containsKey(childName)) {
            final childData = _decode(childVal);
            nodes[childName] = VfsNode(
              path: childFullPath,
              isDir: childData['type'] == 'dir',
              name: childName,
            );
          }
        }
      }
    }

    return nodes.values.toList();
  }
}

class FileSystemException implements Exception {
  final String message;
  final String path;
  FileSystemException(this.message, this.path);

  @override
  String toString() => 'FileSystemException: $message ($path)';
}

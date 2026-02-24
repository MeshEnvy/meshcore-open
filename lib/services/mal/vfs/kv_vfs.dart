import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'vfs.dart';
import '../kv/kv_store.dart';

/// Provides the KvVfs implementation.
VirtualFileSystem getWebVfs(MeshKvStore kvStore) => KvVfs(kvStore);

/// A VirtualFileSystem implementation that uses `MeshKvStore` to simulate
/// a file system. This is primarily used as a fallback on the Web or in
/// highly restricted sandbox environments where `dart:io` cannot be used.
///
/// Note: To support binary data securely in the text-based KV store,
/// file contents are stored as Base64 encoded strings.
class KvVfs extends VirtualFileSystem {
  final MeshKvStore _kvStore;
  late String _nodeId;

  // The prefix used in the KV store key to isolate VFS data from ENV variables
  static const String _vfsPrefix = 'vfs:';

  KvVfs(this._kvStore);

  String _toKvKey(String path) {
    // Normalize path to ensure consistent keys
    final normalized = p.normalize(path);
    return '$_vfsPrefix$normalized';
  }

  @override
  Future<String> init(String nodeId) async {
    _nodeId = nodeId;
    // Since this is KV-backed, the "drive path" is conceptual.
    // We return a normalized conceptual root for this node.
    return '/$nodeId';
  }

  @override
  Future<bool> exists(String path) async {
    final key = _toKvKey(path);
    final val = await _kvStore.get(key, _nodeId);
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

  @override
  Future<void> createDir(String path) async {
    await _ensureParentDirExists(path);

    // We represent a directory by storing a specific marker string
    final key = _toKvKey(path);
    await _kvStore.set(key, '__DIR__', _nodeId);
  }

  @override
  Future<void> createFile(String path) async {
    await _ensureParentDirExists(path);

    // We represent an empty file by storing an empty string
    final key = _toKvKey(path);
    await _kvStore.set(key, '', _nodeId);
  }

  @override
  Future<void> writeAsString(String path, String content) async {
    await _ensureParentDirExists(path);
    final key = _toKvKey(path);

    // Store as plain string text prefix
    await _kvStore.set(key, '__TXT__$content', _nodeId);
  }

  @override
  Future<String> readAsString(String path) async {
    final key = _toKvKey(path);
    final val = await _kvStore.get(key, _nodeId);

    if (val == null) {
      throw FileSystemException('File not found', path);
    }
    if (val == '__DIR__') {
      throw FileSystemException('Path is a directory, not a file', path);
    }

    if (val.startsWith('__TXT__')) {
      return val.substring(7);
    } else {
      throw FileSystemException('Path contains binary data, not text', path);
    }
  }

  // NOTE: For binary methods readAsBytes/writeAsBytes, we would typically base64 encode
  // the data and store it with a '__BIN__' prefix. We omit full binary conversion here
  // to keep the VFS scope focused, but it can be added if Lua scripts need binary images.
  @override
  Future<void> writeAsBytes(String path, Uint8List bytes) async {
    throw UnimplementedError('Binary write not currently implemented in KvVfs');
  }

  @override
  Future<Uint8List> readAsBytes(String path) async {
    throw UnimplementedError('Binary read not currently implemented in KvVfs');
  }

  @override
  Future<void> delete(String path) async {
    final key = _toKvKey(path);
    final val = await _kvStore.get(key, _nodeId);

    if (val == null) return;

    if (val == '__DIR__') {
      // If it's a directory, we must delete all children recursively.
      // This is expensive in KV, we have to scan keys.
      final allKeys = await _kvStore.getKeys(_nodeId);
      final targetPrefix = '$key/';

      for (final k in allKeys) {
        if (k.startsWith(targetPrefix)) {
          await _kvStore.delete(k, _nodeId);
        }
      }
    }

    // Delete the target itself
    await _kvStore.delete(key, _nodeId);
  }

  @override
  Future<List<VfsNode>> list(String path) async {
    final normalizedPath = p.normalize(path);
    final targetPrefix = '$_vfsPrefix$normalizedPath/';

    final allKeys = await _kvStore.getKeys(_nodeId);
    final Map<String, VfsNode> nodes = {};

    for (final key in allKeys) {
      if (key.startsWith(targetPrefix) && key != targetPrefix) {
        final relativePath = key.substring(targetPrefix.length);
        final parts = p.split(relativePath);

        if (parts.isNotEmpty) {
          final childName = parts.first;
          final childFullPath = p.join(normalizedPath, childName);
          final childKey = '$_vfsPrefix$childFullPath';
          final childVal = await _kvStore.get(childKey, _nodeId);

          if (!nodes.containsKey(childName)) {
            nodes[childName] = VfsNode(
              path: childFullPath,
              isDir: childVal == '__DIR__',
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

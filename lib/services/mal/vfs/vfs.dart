import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../utils/platform_info.dart';
import '../kv/kv_store.dart';

import 'native_vfs.dart' if (dart.library.html) 'kv_vfs.dart';

/// Represents a node (file or directory) in the virtual file system.
class VfsNode {
  final String path;
  final bool isDir;
  final String name;

  const VfsNode({required this.path, required this.isDir, required this.name});
}

/// Abstract Virtual File System interface to decouple file operations
/// from `dart:io` for web compatibility.
abstract class VirtualFileSystem {
  /// Returns the singleton instance based on the platform.
  /// If [PlatformInfo.isWeb] is true, this defaults to the `KvVfs` implementation
  /// backed by the provided [kvStore].
  static VirtualFileSystem get(MeshKvStore kvStore) {
    if (PlatformInfo.isWeb) {
      return getWebVfs(kvStore);
    }
    return getNativeVfs();
  }

  /// Initializes the VFS and returns the absolute root drive path.
  Future<String> init();

  /// Checks if a file or directory exists at the given path.
  Future<bool> exists(String path);

  /// Creates a directory at the given path. Recursive by default.
  Future<void> createDir(String path);

  /// Creates a file at the given path. Recursive by default.
  Future<void> createFile(String path);

  /// Writes raw bytes to a file.
  Future<void> writeAsBytes(String path, Uint8List bytes);

  /// Reads raw bytes from a file.
  Future<Uint8List> readAsBytes(String path);

  /// Deletes a file or directory at the given path. Recursive by default.
  Future<void> delete(String path);

  /// Lists the immediate children of the given directory.
  Future<List<VfsNode>> list(String path);

  // --- Convenience String Methods ---

  /// Writes a UTF-8 string to a file.
  Future<void> writeAsString(String path, String content) async {
    final bytes = utf8.encode(content);
    await writeAsBytes(path, Uint8List.fromList(bytes));
  }

  /// Reads a UTF-8 string from a file.
  Future<String> readAsString(String path) async {
    final bytes = await readAsBytes(path);
    return utf8.decode(bytes);
  }
}

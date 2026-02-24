import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../kv/kv_store.dart';
import 'package:path/path.dart' as p;
import 'vfs.dart';

/// Provides the NativeVfs implementation.
VirtualFileSystem getNativeVfs() => NativeVfs();

/// Provides the WebVfs (KvVfs) implementation. Throws an error if called on native.
VirtualFileSystem getWebVfs(MeshKvStore kvStore) {
  throw UnsupportedError(
    'getWebVfs is not supported on native platforms. Use KvVfs directly if needed.',
  );
}

/// A standard `dart:io` implementation of the VirtualFileSystem for native platforms.
class NativeVfs extends VirtualFileSystem {
  late String _drivePath;

  @override
  Future<String> init(String nodeId) async {
    final docsDir = await getApplicationDocumentsDirectory();
    _drivePath = p.join(docsDir.path, nodeId, 'drive');
    final dir = Directory(_drivePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return _drivePath;
  }

  @override
  Future<bool> exists(String path) async {
    final type = await FileSystemEntity.type(path);
    return type != FileSystemEntityType.notFound;
  }

  @override
  Future<void> createDir(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> createFile(String path) async {
    await File(path).create(recursive: true);
  }

  @override
  Future<void> writeAsBytes(String path, Uint8List bytes) async {
    await File(path).writeAsBytes(bytes);
  }

  @override
  Future<Uint8List> readAsBytes(String path) async {
    return await File(path).readAsBytes();
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete(recursive: true);
      return;
    }
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  @override
  Future<List<VfsNode>> list(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      return [];
    }

    final entities = await dir.list().toList();
    return entities.map((e) {
      return VfsNode(
        path: e.path,
        isDir: e is Directory,
        name: e.path.split('/').last,
      );
    }).toList();
  }
}

import 'dart:async';
import 'dart:typed_data';
import '../../../models/contact.dart';
import '../../../models/channel.dart';
import '../../../connector/meshcore_connector.dart';
import 'mal_api.dart';
import 'kv/kv_store.dart';
import 'kv/sqflite_kv.dart';
import 'kv/indexed_db_kv.dart';
import 'vfs/vfs.dart';
import 'package:flutter/foundation.dart';

/// A native Dart implementation of the `MalApi` interface that is backed
/// by the live `MeshCoreConnector` for networking, `MeshKvStore` for variables/storage,
/// and `VirtualFileSystem` for flat file operations.
class ConnectorMalApi implements MalApi {
  final MeshCoreConnector _connector;
  late final MeshKvStore _kvStore;
  late final VirtualFileSystem _vfs;
  String _homePath = '';

  ConnectorMalApi({required MeshCoreConnector connector})
    : _connector = connector;

  @override
  Future<void> init() async {
    final MeshKvStore kvStore;
    if (kIsWeb) {
      kvStore = getIndexedDbKvStore();
    } else {
      kvStore = SqfliteKvStore.instance;
    }

    await kvStore.init();
    _kvStore = kvStore;
    _vfs = VirtualFileSystem.get(kvStore);
    _homePath = await _vfs.init();
  }

  @override
  String get homePath => _homePath;

  @override
  Contact? get selfNode {
    // If not connected, return null
    if (!_connector.isConnected) return null;

    // Attempt to synthesize the local node based on self context
    final selfKey = _connector.selfPublicKey;
    if (selfKey == null) return null;

    return Contact(
      publicKey: selfKey,
      name: _connector.selfName ?? 'Me',
      type: 0, // advTypeChat
      pathLength: 0,
      path: Uint8List(0),
      latitude: _connector.selfLatitude,
      longitude: _connector.selfLongitude,
      lastSeen: DateTime.now(),
    );
  }

  @override
  List<Contact> get knownNodes => _connector.contacts;

  @override
  Contact? getNode(String id) {
    try {
      return _connector.contacts.firstWhere((c) => c.publicKeyHex == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> sendText(
    String text, {
    String? destNodeId,
    int? channelIndex,
    int? portNum,
  }) async {
    if (!_connector.isConnected) {
      if (kDebugMode) print('[MalApi] Cannot sendText: Not connected.');
      return null;
    }

    try {
      if (channelIndex != null) {
        final channel = _connector.channels.cast<Channel?>().firstWhere(
          (c) => c?.index == channelIndex,
          orElse: () => null,
        );
        if (channel == null) {
          if (kDebugMode) {
            print('[MalApi] sendText failed: Channel $channelIndex not found.');
          }
          return null;
        }
        await _connector.sendChannelMessage(channel, text);
        return 'queued_ch_$channelIndex';
      }

      if (destNodeId != null) {
        final message = await _connector.sendText(text, destNodeId);
        return message?.messageId;
      }

      if (kDebugMode)
        print('[MalApi] sendText failed: No destination provided.');
      return null;
    } catch (e) {
      if (kDebugMode) print('[MalApi] sendText failed: $e');
      return null;
    }
  }

  @override
  Future<String?> sendData(
    List<int> payloadBytes, {
    String? destNodeId,
    int? channelIndex,
    required int portNum,
    bool wantAck = false,
  }) async {
    if (!_connector.isConnected) {
      if (kDebugMode) print('[MalApi] Cannot sendData: Not connected.');
      return null;
    }

    try {
      if (destNodeId != null) {
        final message = await _connector.sendData(
          Uint8List.fromList(payloadBytes),
          destContactKeyHex: destNodeId,
          portNum: portNum,
          wantAck: wantAck,
        );
        return message?.messageId;
      }

      // Channel data (PAYLOAD_TYPE_GRP_DATA) is not yet exposed via a dedicated
      // MeshCore connector command. For now, we return null.
      if (kDebugMode) {
        print(
          '[MalApi] sendData to channel $channelIndex with port $portNum not yet supported by MeshCore protocol.',
        );
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('[MalApi] sendData failed: $e');
      return null;
    }
  }

  // --------------------------------------------------------------------------
  // Environment Variables
  // --------------------------------------------------------------------------

  @override
  Future<String?> getEnv(String key) async {
    return _kvStore.get(key);
  }

  @override
  Future<void> setEnv(String key, String value) async {
    await _kvStore.set(key, value);
  }

  // --------------------------------------------------------------------------
  // Key-Value Store
  // --------------------------------------------------------------------------

  @override
  Future<String?> getKey(String key) => _kvStore.get(key);

  @override
  Future<void> setKey(String key, String value) => _kvStore.set(key, value);

  @override
  Future<void> deleteKey(String key) => _kvStore.delete(key);

  @override
  Future<List<String>> getKeys() => _kvStore.getKeys();

  // --------------------------------------------------------------------------
  // Virtual File System
  // --------------------------------------------------------------------------

  @override
  Future<bool> fexists(String path) {
    return _vfs.exists(path);
  }

  @override
  Future<List<VfsNode>> flist(String path) {
    return _vfs.list(path);
  }

  @override
  Future<void> fcreate(String path) {
    return _vfs.createFile(path);
  }

  @override
  Future<void> mkdir(String path) {
    return _vfs.createDir(path);
  }

  @override
  Future<void> rmdir(String path) {
    return _vfs.delete(path);
  }

  @override
  Future<void> rm(String path) {
    return _vfs.delete(path);
  }

  @override
  Future<void> fwrite(String path, String content) {
    return _vfs.writeAsString(path, content);
  }

  @override
  Future<void> fwriteBytes(String path, Uint8List bytes) {
    return _vfs.writeAsBytes(path, bytes);
  }

  @override
  Future<String> fread(String path) {
    return _vfs.readAsString(path);
  }

  @override
  Future<Uint8List> freadBytes(String path) {
    return _vfs.readAsBytes(path);
  }
}

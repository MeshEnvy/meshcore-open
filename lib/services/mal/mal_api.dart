import 'dart:async';
import 'dart:typed_data';
import '../../models/contact.dart';
import 'vfs/vfs.dart';

/// The unified Mesh Abstraction Layer (MAL) API interface.
/// This interface provides a global, flat namespace for interacting with the
/// underlying mesh network, scoped key-value store, environment variables,
/// and virtual file system.
abstract class MalApi {
  /// Initializes the MAL provider.
  Future<void> init();

  // --------------------------------------------------------------------------
  // Network / Mesh Operations
  // --------------------------------------------------------------------------

  /// The local node representing the user ("me").
  Contact? get selfNode;

  /// Returns a list of all currently known nodes in the mesh network.
  List<Contact> get knownNodes;

  /// Retrieves a specific node by its ID (public key hex).
  Contact? getNode(String id);

  /// Sends a text message to a specific destination node or a channel.
  /// This typically targets the "Text" port/app (Port 1 in Meshtastic, 0x02/0x05 in MeshCore).
  /// Set [destNodeId] for a direct message, or [channelIndex] for a channel message.
  Future<String?> sendText(
    String text, {
    String? destNodeId,
    int? channelIndex,
    int? portNum,
  });

  /// Sends raw payload bytes to a specified port on the destination node or channel.
  /// Ports allow targeting specific sub-applications (e.g., Telemetry, Sensors, Lua scripts).
  Future<String?> sendData(
    List<int> payloadBytes, {
    String? destNodeId,
    int? channelIndex,
    required int portNum,
    bool wantAck = false,
  });

  // --------------------------------------------------------------------------
  // Environment Variables
  // --------------------------------------------------------------------------

  Future<String?> getEnv(String key);
  Future<void> setEnv(String key, String value);

  // --------------------------------------------------------------------------
  // Key-Value Store
  // --------------------------------------------------------------------------

  Future<String?> getKey(String key);
  Future<void> setKey(String key, String value);
  Future<void> deleteKey(String key);
  Future<List<String>> getKeys();

  // --------------------------------------------------------------------------
  // Virtual File System
  // --------------------------------------------------------------------------

  Future<bool> fexists(String path);
  Future<void> bindToNode(String nodeId);
  String get homePath;
  Future<List<VfsNode>> flist(String path);
  Future<void> fcreate(String path);
  Future<void> mkdir(String path);
  Future<void> rmdir(String path);
  Future<void> rm(String path);
  Future<void> fwrite(String path, String content);
  Future<void> fwriteBytes(String path, Uint8List bytes);
  Future<String> fread(String path);
  Future<Uint8List> freadBytes(String path);
}

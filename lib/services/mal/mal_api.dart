import 'dart:async';
import 'dart:typed_data';
import '../../models/contact.dart';
import 'vfs/vfs.dart';

/// A lightweight, Lua-friendly view of an incoming direct message.
class MeshIncomingMessage {
  /// Plain-text content of the message.
  final String text;

  /// Public-key hex of the sender — pass this to [MalApi.sendText] to reply.
  final String from;

  /// Display name of the sender, if known.
  final String senderName;

  const MeshIncomingMessage({
    required this.text,
    required this.from,
    required this.senderName,
  });
}

/// The unified Mesh Abstraction Layer (MAL) API interface.
/// This interface provides a global, flat namespace for interacting with the
/// underlying mesh network, scoped key-value store, environment variables,
/// and virtual file system.
abstract class MalApi {
  /// Initializes the MAL provider.
  Future<void> init();

  // --------------------------------------------------------------------------
  // Messaging Events
  // --------------------------------------------------------------------------

  /// Broadcast stream of incoming direct messages.
  /// Emits one [MeshIncomingMessage] for every received, non-CLI, non-self DM.
  Stream<MeshIncomingMessage> get incomingMessages;

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

  Future<String?> getKey(String key, {String? scope});
  Future<void> setKey(String key, String value, {String? scope});
  Future<void> deleteKey(String key, {String? scope});
  Future<List<String>> getKeys({String? scope});

  // --------------------------------------------------------------------------
  // Virtual File System
  // --------------------------------------------------------------------------

  Future<bool> fexists(String path);
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

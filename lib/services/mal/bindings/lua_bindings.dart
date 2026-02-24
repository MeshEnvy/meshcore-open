import 'package:lua_dardo/lua.dart';
import '../mal_api.dart';

/// Binds the native Dart `MalApi` implementation into a `lua_dardo` state
/// under a single global `mal` table.
class LuaMalBindings {
  /// Injects the `mal.*` namespace into the provided [state].
  static void register(LuaState state, {required MalApi api}) {
    state.newTable(); // the `mal` table

    // --------------------------------------------------------------------------
    // Network
    // --------------------------------------------------------------------------

    // mal.getKnownNodes
    state.pushDartFunction((LuaState ls) {
      final nodes = api.knownNodes;
      ls.newTable();
      for (final node in nodes) {
        ls.pushString(node.publicKeyHex);
        ls.newTable();
        ls.pushString(node.name);
        ls.setField(-2, "longName");
        ls.pushString(node.typeLabel);
        ls.setField(-2, "type");
        ls.setTable(-3);
      }
      return 1;
    });
    state.setField(-2, "getKnownNodes");

    // mal.getNode(id)
    state.pushDartFunction((LuaState ls) {
      final id = ls.checkString(1);
      if (id == null) return 0;
      final node = api.getNode(id);
      if (node == null) {
        ls.pushNil();
        return 1;
      }
      ls.newTable();
      ls.pushString(node.name);
      ls.setField(-2, "longName");
      ls.pushString(node.typeLabel);
      ls.setField(-2, "type");
      return 1;
    });
    state.setField(-2, "getNode");

    // mal.sendText(text, destination)
    // destination can be a string (node ID) or a number (channel index)
    state.pushDartFunction((LuaState ls) {
      final text = ls.checkString(1);
      if (text == null) return 0;

      String? destNodeId;
      int? channelIndex;
      int? portNum;

      if (ls.isString(2)) {
        destNodeId = ls.toStr(2);
      } else if (ls.isNumber(2)) {
        channelIndex = ls.toNumber(2).toInt();
      }

      if (ls.isNumber(3)) {
        portNum = ls.toNumber(3).toInt();
      }

      api.sendText(
        text,
        destNodeId: destNodeId,
        channelIndex: channelIndex,
        portNum: portNum,
      );
      return 0;
    });
    state.setField(-2, "sendText");

    // mal.sendData(payload, port, destination)
    // destination can be a string (node ID) or a number (channel index)
    state.pushDartFunction((LuaState ls) {
      final payload = ls.toStr(1);
      final port = ls.toNumber(2).toInt();
      if (payload == null) return 0;

      String? destNodeId;
      int? channelIndex;

      if (ls.isString(3)) {
        destNodeId = ls.toStr(3);
      } else if (ls.isNumber(3)) {
        channelIndex = ls.toNumber(3).toInt();
      }

      api.sendData(
        payload.codeUnits,
        destNodeId: destNodeId,
        channelIndex: channelIndex,
        portNum: port,
      );
      return 0;
    });
    state.setField(-2, "sendBytes");

    // --------------------------------------------------------------------------
    // Environment Variables
    // --------------------------------------------------------------------------

    // mal.getEnv
    state.pushDartFunction((LuaState ls) {
      final key = ls.checkString(1);
      if (key == null) return 0;

      // Since we can't await in sync DartFunction, we return nil for now
      // but trigger the fetch.
      // TODO: Implement a sync cache for environment variables.
      ls.pushNil();
      return 1;
    });
    state.setField(-2, "getEnv");

    // mal.setEnv
    state.pushDartFunction((LuaState ls) {
      final key = ls.checkString(1);
      final val = ls.checkString(2);
      if (key != null && val != null) {
        api.setEnv(key, val);
      }
      return 0;
    });
    state.setField(-2, "setEnv");

    // --------------------------------------------------------------------------
    // Key-Value Store
    // --------------------------------------------------------------------------

    state.pushDartFunction((LuaState ls) {
      final key = ls.checkString(1);
      final val = ls.checkString(2);
      if (key != null && val != null) {
        api.setKey(key, val);
      }
      return 0;
    });
    state.setField(-2, "setKey");

    state.pushDartFunction((LuaState ls) {
      ls.pushNil();
      return 1;
    });
    state.setField(-2, "getKey");

    // --------------------------------------------------------------------------
    // Virtual File System
    // --------------------------------------------------------------------------

    state.pushDartFunction((LuaState ls) {
      final path = ls.checkString(1);
      final content = ls.checkString(2);
      if (path != null && content != null) {
        api.fwrite(path, content);
      }
      return 0;
    });
    state.setField(-2, "fwrite");

    state.pushDartFunction((LuaState ls) {
      // We can't return content sync, so we return nil.
      // Scripts should use fwrite for now.
      ls.pushNil();
      return 1;
    });
    state.setField(-2, "fread");

    state.pushDartFunction((LuaState ls) {
      final path = ls.checkString(1);
      if (path != null) {
        api.rm(path);
      }
      return 0;
    });
    state.setField(-2, "rm");

    state.pushDartFunction((LuaState ls) {
      final path = ls.checkString(1);
      if (path != null) {
        api.mkdir(path);
      }
      return 0;
    });
    state.setField(-2, "mkdir");

    state.pushDartFunction((LuaState ls) {
      final path = ls.checkString(1);
      if (path != null) {
        api.rmdir(path);
      }
      return 0;
    });
    state.setField(-2, "rmdir");

    state.pushDartFunction((LuaState ls) {
      // fexists is hard to do sync without a cache.
      // Returning false is safer than true if we don't know.
      ls.pushBoolean(false);
      return 1;
    });
    state.setField(-2, "fexists");

    // Dummy handle functions
    state.pushDartFunction((LuaState ls) {
      final path = ls.checkString(1);
      if (path != null) {
        ls.pushString(path);
        return 1;
      }
      return 0;
    });
    state.setField(-2, "fopen");

    state.pushDartFunction((LuaState ls) {
      return 0;
    });
    state.setField(-2, "fclose");

    // Push `mal` table to global
    state.setGlobal("mal");
  }
}

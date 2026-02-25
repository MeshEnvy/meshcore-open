import 'package:lua_dardo/lua.dart';
import '../mal_api.dart';
import '../../lua_service.dart';

/// Holds the synchronous KV cache and the list of async write futures that
/// have been fired during a Lua script run.
///
/// Call [flush] after `doString` to ensure all writes are committed to the
/// backing store before the next script run loads the cache.
class LuaMalContext {
  /// Write-through cache keyed by `"$scope:$key"` (or just `"$key"` when no
  /// scope is provided).  Pre-populated before Lua execution begins.
  final Map<String, String> kvCache;

  final List<Future<void>> _pendingWrites = [];

  LuaMalContext({required this.kvCache});

  /// Register a write future so it can be awaited by [flush].
  void addPendingWrite(Future<void> f) => _pendingWrites.add(f);

  /// Awaits all pending KV store writes and clears the queue.
  /// Must be called after `doString` to guarantee persistence before the next
  /// script run's [LuaMalBindings.loadKvCache] executes.
  Future<void> flush() async {
    if (_pendingWrites.isEmpty) return;
    await Future.wait(_pendingWrites);
    _pendingWrites.clear();
  }
}

/// Binds the native Dart `MalApi` implementation into a `lua_dardo` state
/// under a single global `mal` table.
class LuaMalBindings {
  /// Pre-loads all KV entries (default scope) into a synchronous cache so that
  /// `mal.getKey` can return values synchronously from within Lua.
  ///
  /// Call this before [register] and pass the returned [LuaMalContext].
  static Future<LuaMalContext> loadKvCache(MalApi api) async {
    final cache = <String, String>{};
    try {
      // Use getValues for a single round-trip where available.
      final keys = await api.getKeys();
      for (final key in keys) {
        final val = await api.getKey(key);
        if (val != null) {
          cache[key] = val;
        }
      }
    } catch (_) {
      // If loading fails, start with an empty cache – writes will still work.
    }
    return LuaMalContext(kvCache: cache);
  }

  /// Injects the `mal.*` namespace into the provided [state].
  ///
  /// [context] must be a [LuaMalContext] returned by [loadKvCache].  After
  /// `doString` completes, the caller must `await context.flush()` to ensure
  /// all writes have been committed to the backing store.
  static void register(
    LuaState state, {
    required MalApi api,
    required LuaMalContext context,
    LuaProcess? process,
  }) {
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
    //
    // Uses a synchronous write-through cache (context.kvCache) pre-populated
    // before execution so reads are always consistent within a script run.
    // Writes are tracked in context._pendingWrites; call context.flush() after
    // doString to guarantee they have committed before the next run.
    // --------------------------------------------------------------------------

    // mal.setKey(key, value [, scope])
    state.pushDartFunction((LuaState ls) {
      final key = ls.checkString(1);
      final val = ls.checkString(2);
      final scope = ls.isString(3) ? ls.toStr(3) : null;
      if (key != null && val != null) {
        // Write-through: update cache immediately so getKey sees the new value.
        final cacheKey = scope != null ? '$scope:$key' : key;
        context.kvCache[cacheKey] = val;
        // Track the write future so runScript can await it after doString.
        context.addPendingWrite(api.setKey(key, val, scope: scope));
      }
      return 0;
    });
    state.setField(-2, "setKey");

    // mal.getKey(key [, scope])
    state.pushDartFunction((LuaState ls) {
      final key = ls.checkString(1);
      if (key == null) {
        ls.pushNil();
        return 1;
      }
      final scope = ls.isString(2) ? ls.toStr(2) : null;
      final cacheKey = scope != null ? '$scope:$key' : key;
      final val = context.kvCache[cacheKey];
      if (val == null) {
        ls.pushNil();
      } else {
        ls.pushString(val);
      }
      return 1;
    });
    state.setField(-2, "getKey");

    // mal.deleteKey(key [, scope])
    state.pushDartFunction((LuaState ls) {
      final key = ls.checkString(1);
      if (key == null) return 0;
      final scope = ls.isString(2) ? ls.toStr(2) : null;
      final cacheKey = scope != null ? '$scope:$key' : key;
      context.kvCache.remove(cacheKey);
      context.addPendingWrite(api.deleteKey(key, scope: scope));
      return 0;
    });
    state.setField(-2, "deleteKey");

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

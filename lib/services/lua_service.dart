import 'package:flutter/foundation.dart';
import 'package:lua_dardo/lua.dart';
// ignore: implementation_imports
import 'package:lua_dardo/src/stdlib/basic_lib.dart';
// ignore: implementation_imports
import 'package:lua_dardo/src/stdlib/math_lib.dart';
// ignore: implementation_imports
import 'package:lua_dardo/src/stdlib/string_lib.dart';
// ignore: implementation_imports
import 'package:lua_dardo/src/stdlib/table_lib.dart';
import 'package:uuid/uuid.dart';

import '../utils/app_logger.dart';
import 'mal/mal_api.dart';
import 'mal/bindings/lua_bindings.dart';

enum LuaProcessStatus { running, completed, error, killed }

class LuaProcess extends ChangeNotifier {
  final String id;
  final String name;
  final DateTime startTime;
  LuaProcessStatus status;
  final List<String> logs = [];
  LuaState? state;

  /// Number of active listeners (e.g., mal.onMessage callbacks)
  int activeListeners = 0;

  /// List of callbacks to invoke when this process is killed
  final List<VoidCallback> _disposalCallbacks = [];

  LuaProcess({required this.name, this.status = LuaProcessStatus.running})
    : id = const Uuid().v4(),
      startTime = DateTime.now();

  void addLog(String message) {
    logs.add('[${DateTime.now().toIso8601String().split('T').last}] $message');
    notifyListeners();
  }

  void updateStatus(LuaProcessStatus newStatus) {
    status = newStatus;
    notifyListeners();
  }

  void addDisposalCallback(VoidCallback callback) {
    _disposalCallbacks.add(callback);
  }

  void kill() {
    if (status == LuaProcessStatus.killed ||
        status == LuaProcessStatus.completed ||
        status == LuaProcessStatus.error) {
      return;
    }

    status = LuaProcessStatus.killed;

    for (final callback in _disposalCallbacks) {
      try {
        callback();
      } catch (e) {
        appLogger.error(
          'Error in LuaProcess disposal callback: $e',
          tag: 'LuaProcess',
        );
      }
    }
    _disposalCallbacks.clear();
    activeListeners = 0;

    if (state != null) {
      // Current lua_dardo doesn't have an explicit close/dispose method.
      // But clearing references helps.
      state = null;
    }

    addLog('--- Process Terminated by User ---');
    // notifyListeners is called by addLog
  }
}

class LuaService extends ChangeNotifier {
  static final LuaService _instance = LuaService._internal();
  factory LuaService() => _instance;
  LuaService._internal();

  bool _isInitialized = false;
  final List<LuaProcess> _processes = [];

  List<LuaProcess> get processes => List.unmodifiable(_processes);

  /// Public wrapper around [notifyListeners] so that external callers
  /// (e.g., the Tasks panel) can trigger a UI rebuild after mutating
  /// process state (e.g., calling [LuaProcess.kill]).
  void notify() => notifyListeners();

  Future<void> initialize(MalApi malApi) async {
    if (_isInitialized) {
      appLogger.info(
        'LuaService already initialized, re-running autoexec...',
        tag: 'LuaService',
      );
    } else {
      appLogger.info('Initializing LuaService', tag: 'LuaService');
      _isInitialized = true;
    }

    if (kDebugMode) print('[LuaService] Initializing/Running...');
    try {
      final drivePath = malApi.homePath;
      final autoexecPath = '$drivePath/autoexec.lua';

      // Ensure autoexec.lua existence for testing if not present
      if (!await malApi.fexists(autoexecPath)) {
        appLogger.info(
          'Creating default autoexec.lua at $autoexecPath',
          tag: 'LuaService',
        );
        await malApi.fwrite(
          autoexecPath,
          '-- Auto-generated autoexec.lua\nprint("MeshCore Lua Service Started")\n',
        );
      }

      // Run autoexec
      if (await malApi.fexists(autoexecPath)) {
        appLogger.info(
          'Executing autoexec.lua at $autoexecPath...',
          tag: 'LuaService',
        );
        if (kDebugMode) print('[LuaService] Executing autoexec.lua...');

        final content = await malApi.fread(autoexecPath);
        await runScript(malApi, content, name: 'autoexec.lua');
      } else {
        appLogger.info(
          'No autoexec.lua found at $autoexecPath',
          tag: 'LuaService',
        );
        if (kDebugMode) print('[LuaService] No autoexec.lua found.');
      }
    } catch (e) {
      appLogger.error('Error executing autoexec.lua: $e', tag: 'LuaService');
      if (kDebugMode) print('[LuaService] Error: $e');
    }
  }

  /// Wraps [content] in a Lua xpcall envelope so that any runtime error
  /// (including internal lua_dardo throws like "Null, not a table!") is caught
  /// at the Lua level and surfaced as a clean error message in the process log.
  static String _wrapInXpcall(String content, String scriptName) {
    // level=0 on the re-raise so Lua's error() doesn't prepend a second
    // source location — the location is already inside __err from the
    // innermost error that xpcall caught.
    return '''
local __ok, __err = xpcall(function()
$content
end, tostring)
if not __ok then
  error("[$scriptName] " .. tostring(__err or "unknown error"), 0)
end
''';
  }

  Future<LuaProcess> runScript(
    MalApi malApi,
    String content, {
    String name = 'Unnamed Script',
  }) async {
    final process = LuaProcess(name: name);
    _processes.add(process);
    notifyListeners();

    try {
      LuaState state = LuaState.newState();
      process.state = state;

      // Load standard libraries selectively
      state.requireF("_G", BasicLib.openBaseLib, true);
      state.pop(1);
      state.requireF("table", TableLib.openTableLib, true);
      state.pop(1);
      state.requireF("string", StringLib.openStringLib, true);
      state.pop(1);
      state.requireF("math", MathLib.openMathLib, true);
      state.pop(1);

      // Bridge Lua print to appLogger and the specific process
      state.pushDartFunction((ls) {
        final n = ls.getTop();
        final sb = StringBuffer();
        for (var i = 1; i <= n; i++) {
          sb.write(ls.toStr(i));
          if (i < n) sb.write('\t');
        }
        final msg = sb.toString();

        process.addLog(msg);
        appLogger.info('[$name] $msg', tag: 'LuaService');
        if (kDebugMode) print('[$name] $msg');

        // Notify LuaService listeners so combined log views can update
        notifyListeners();
        return 0;
      });
      state.setGlobal("print");

      appLogger.info(
        'Registering Mesh Abstraction Layer into Lua for $name...',
        tag: 'LuaService',
      );

      // Pre-load the KV write-through cache so synchronous getKey reads inside
      // Lua see persisted values.  The context also tracks pending write Futures
      // so we can flush them after doString.
      final malContext = await LuaMalBindings.loadKvCache(malApi);

      // Inject MAL Bindings (Global 'mal' table), passing process context
      LuaMalBindings.register(
        state,
        api: malApi,
        context: malContext,
        process: process,
      );

      // Wrap user script in xpcall so Lua runtime errors (e.g.
      // "Null, not a table!") are caught at the Lua level and reported
      // with the script name rather than as opaque Dart exceptions.
      // Pass the script name as chunkName so proto.source is set correctly
      // (ensures line numbers reference the right file).
      final result = state.doString(
        _wrapInXpcall(content, name),
        chunkName: name,
      );

      // Await all KV writes triggered during the script so they are committed
      // to the backing store before any subsequent run loads the cache.
      await malContext.flush();
      if (kDebugMode) {
        print(
          '[LuaService] $name result: $result (type: ${result.runtimeType})',
        );
      }

      // If the process was killed during execution, don't update status normally
      if (process.status != LuaProcessStatus.killed) {
        final String resultStr = result.toString();
        final bool isSuccess =
            (resultStr.contains('LUA_OK') ||
            resultStr.contains('lua_ok') ||
            resultStr == '0' ||
            (result as dynamic) == 0 ||
            (result as dynamic) == true);

        if (!isSuccess) {
          String? errorMsg;
          if (state.getTop() > 0) {
            errorMsg = state.toStr(-1);
          }
          errorMsg ??= 'Unknown error ($result)';
          // Strip "Exception: " boilerplate that Dart injects into thrown
          // exceptions. Use replaceAll because our [scriptName] prefix
          // may appear before it.
          errorMsg = errorMsg.replaceAll('Exception: ', '');

          process.addLog('Error: $errorMsg');
          process.updateStatus(LuaProcessStatus.error);
          notifyListeners();

          appLogger.error(
            '$name execution failed (code $result): $errorMsg',
            tag: 'LuaService',
          );
          if (kDebugMode) {
            print('[LuaService] $name Execution failed: $errorMsg');
          }
        } else {
          // If no active listeners were registered, the script is complete.
          // Otherwise, we leave it in the "running" state as a daemon.
          if (process.activeListeners == 0) {
            process.updateStatus(LuaProcessStatus.completed);
            notifyListeners();
            process.addLog('--- Script finished ---');
            appLogger.info(
              '$name execution completed (doString returned).',
              tag: 'LuaService',
            );
            if (kDebugMode) print('[LuaService] $name Execution completed.');
          } else {
            process.addLog(
              '--- Script finished, staying resident with '
              '${process.activeListeners} active listener(s) — '
              'press Stop to terminate ---',
            );
            appLogger.info(
              '$name is staying resident with ${process.activeListeners} active listener(s).',
              tag: 'LuaService',
            );
            if (kDebugMode) {
              print(
                '[LuaService] $name staying resident '
                '(${process.activeListeners} listeners).',
              );
            }
          }
        }
      }
    } catch (e, stackTrace) {
      if (process.status != LuaProcessStatus.killed) {
        // Strip the "Exception: " prefix Dart wraps around thrown exceptions.
        String msg = e.toString().replaceAll('Exception: ', '');
        process.addLog('Runtime error in $name: $msg');
        process.updateStatus(LuaProcessStatus.error);
        notifyListeners();
      }
      appLogger.error(
        'Unhandled exception while executing $name: $e\n$stackTrace',
        tag: 'LuaService',
      );
      if (kDebugMode) {
        print('[LuaService] $name Unhandled exception: $e\n$stackTrace');
      }
    }

    return process;
  }
}

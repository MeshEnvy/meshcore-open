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

import '../utils/app_logger.dart';
import 'mal/mal_api.dart';
import 'mal/bindings/lua_bindings.dart';

class LuaService {
  static final LuaService _instance = LuaService._internal();
  factory LuaService() => _instance;
  LuaService._internal();

  bool _isInitialized = false;

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

        LuaState state = LuaState.newState();

        // Load standard libraries selectively
        state.requireF("_G", BasicLib.openBaseLib, true);
        state.pop(1);
        state.requireF("table", TableLib.openTableLib, true);
        state.pop(1);
        state.requireF("string", StringLib.openStringLib, true);
        state.pop(1);
        state.requireF("math", MathLib.openMathLib, true);
        state.pop(1);

        // Bridge Lua print to appLogger
        state.pushDartFunction((ls) {
          final n = ls.getTop();
          final sb = StringBuffer();
          for (var i = 1; i <= n; i++) {
            sb.write(ls.toStr(i));
            if (i < n) sb.write('\t');
          }
          final msg = sb.toString();
          appLogger.info('[Lua] $msg', tag: 'LuaService');
          if (kDebugMode) print('[Lua] $msg');
          return 0;
        });
        state.setGlobal("print");

        appLogger.info(
          'Registering Mesh Abstraction Layer into Lua...',
          tag: 'LuaService',
        );

        // Inject MAL Bindings (Global 'mal' table)
        LuaMalBindings.register(state, api: malApi);

        final result = state.doString(content);
        if (kDebugMode) {
          print(
            '[LuaService] autoexec result: $result (type: ${result.runtimeType})',
          );
        }

        // In some versions of lua_dardo, doString returns ThreadStatus (enum)
        // In others it might return int or bool.
        final bool isSuccess =
            (result == 0 ||
            result == true ||
            result.toString().endsWith('LUA_OK') ||
            result.toString().endsWith('lua_ok'));

        if (!isSuccess) {
          String? errorMsg;
          if (state.getTop() > 0) {
            errorMsg = state.toStr(-1);
          }
          errorMsg ??= 'Unknown error ($result)';

          appLogger.error(
            'autoexec.lua execution failed (code $result): $errorMsg',
            tag: 'LuaService',
          );
          if (kDebugMode) print('[LuaService] Execution failed: $errorMsg');
        } else {
          appLogger.info(
            'autoexec.lua execution completed.',
            tag: 'LuaService',
          );
          if (kDebugMode) print('[LuaService] Execution completed.');
        }
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
}

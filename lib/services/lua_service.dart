import 'package:flutter/foundation.dart';
import 'package:lua_dardo/lua.dart';
import '../utils/app_logger.dart';
import 'mal/mal_api.dart';
import 'mal/bindings/lua_bindings.dart';

class LuaService {
  Future<void> initialize(MalApi malApi) async {
    appLogger.info('Initializing LuaService', tag: 'LuaService');
    if (kDebugMode) print('[LuaService] Initializing...');
    try {
      final drivePath = malApi.homePath;

      appLogger.info('LuaService Drive: $drivePath', tag: 'LuaService');
      if (kDebugMode) print('[LuaService] Dir: $drivePath');

      final autoexecPath = '$drivePath/autoexec.lua';

      // Optionally run autoexec if it exists
      if (await malApi.fexists(autoexecPath)) {
        appLogger.info(
          'Found autoexec.lua at $autoexecPath, executing...',
          tag: 'LuaService',
        );
        if (kDebugMode) print('[LuaService] Found autoexec.lua, executing...');

        final content = await malApi.fread(autoexecPath);

        LuaState state = LuaState.newState();
        state.openLibs();

        appLogger.info(
          'Registering Mesh Abstraction Layer into Lua...',
          tag: 'LuaService',
        );
        if (kDebugMode) print('[LuaService] Registering MAL...');

        // Inject MAL Bindings (Global 'mal' table)
        LuaMalBindings.register(state, api: malApi);

        state.doString(content);
        appLogger.info('autoexec.lua execution completed.', tag: 'LuaService');
        if (kDebugMode) print('[LuaService] Execution completed.');
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

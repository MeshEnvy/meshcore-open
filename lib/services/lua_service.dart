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
import '../utils/platform_info.dart';
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

        // Load standard libraries selectively to avoid crashes on Web.
        // We avoid openLibs() because it attempts to load 'package' and 'os' libraries
        // which crash on Web/Chrome due to Platform.pathSeparator usage in lua_dardo ^0.0.5.
        // The most essential libraries (Base, Table, String, Math) are safe.
        state.requireF("_G", BasicLib.openBaseLib, true);
        state.pop(1);
        state.requireF("table", TableLib.openTableLib, true);
        state.pop(1);
        state.requireF("string", StringLib.openStringLib, true);
        state.pop(1);
        state.requireF("math", MathLib.openMathLib, true);
        state.pop(1);

        // We intentionally skip PackageLib and OSLib on Web/Chrome as they depend on Platform.
        // MeshCore provides its own system/file access via the 'mal' table.
        if (!PlatformInfo.isWeb) {
          // On native, we could potentially load them if needed, but keeping it
          // minimal and consistent across platforms is usually better for Mesh scripts.
          // state.requireF("package", PackageLib.openPackageLib, true);
          // state.pop(1);
        }

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

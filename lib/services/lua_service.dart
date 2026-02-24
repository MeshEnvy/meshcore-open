import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:lua_dardo/lua.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

class LuaService {
  Future<void> initialize() async {
    appLogger.info('Initializing LuaService', tag: 'LuaService');
    if (kDebugMode) print('[LuaService] Initializing...');
    try {
      final dir = await getApplicationDocumentsDirectory();
      appLogger.info('LuaService: ${dir.path}', tag: 'LuaService');
      if (kDebugMode) print('[LuaService] Dir: ${dir.path}');

      // The sandbox path will be: {appDocsDir}/drive/autoexec.lua
      final autoexecFile = File('${dir.path}/drive/autoexec.lua');
      appLogger.info('LuaService: ${autoexecFile.path}', tag: 'LuaService');
      if (kDebugMode) print('[LuaService] Autoexec file: ${autoexecFile.path}');

      if (await autoexecFile.exists()) {
        appLogger.info(
          'Found autoexec.lua at ${autoexecFile.path}, executing...',
          tag: 'LuaService',
        );
        if (kDebugMode) print('[LuaService] Found autoexec.lua, executing...');
        final content = await autoexecFile.readAsString();

        LuaState state = LuaState.newState();
        state.openLibs();

        appLogger.info(
          'Injecting Environment Variables into Lua...',
          tag: 'LuaService',
        );
        if (kDebugMode) {
          print('[LuaService] Injecting Environment Variables...');
        }

        final prefs = await SharedPreferences.getInstance();
        const prefix = 'secret:';
        final envVars = <String, String>{};
        for (final key in prefs.getKeys()) {
          if (key.startsWith(prefix)) {
            final k = key.substring(prefix.length);
            envVars[k] = prefs.getString(key) ?? '';
          }
        }

        // Replace `os.getenv` with our custom function
        state.getGlobal('os');
        if (state.isTable(-1)) {
          state.pushDartFunction((LuaState ls) {
            final arg = ls.checkString(1);
            if (arg != null && envVars.containsKey(arg)) {
              ls.pushString(envVars[arg]!);
            } else {
              ls.pushNil();
            }
            return 1;
          });
          state.setField(-2, 'getenv');
        }
        state.pop(1); // pop 'os' table

        state.doString(content);
        appLogger.info('autoexec.lua execution completed.', tag: 'LuaService');
        if (kDebugMode) print('[LuaService] Execution completed.');
      } else {
        appLogger.info(
          'No autoexec.lua found at ${autoexecFile.path}',
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

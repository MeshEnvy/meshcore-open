// ignore_for_file: avoid_print
import 'package:flutter/widgets.dart';
import 'package:lua_dardo/lua.dart';
// ignore: implementation_imports
import 'package:lua_dardo/src/stdlib/basic_lib.dart';
// ignore: implementation_imports
import 'package:lua_dardo/src/stdlib/math_lib.dart';
// ignore: implementation_imports
import 'package:lua_dardo/src/stdlib/string_lib.dart';
// ignore: implementation_imports
import 'package:lua_dardo/src/stdlib/table_lib.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/services/mal/mal_provider.dart';
import 'package:meshcore_open/services/mal/bindings/lua_bindings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('--- Testing Flat MalApi Lua Execution ---');

  // Fake MeshCoreConnector
  final connector = MeshCoreConnector();

  // preparartion handled by init()

  // Prepare Flat API implementation
  final malApi = ConnectorMalApi(connector: connector);
  await malApi.init();

  // Setup Lua Environment
  LuaState ls = LuaState.newState();

  // Load standard libraries selectively (Web-safe subset)
  ls.requireF("_G", BasicLib.openBaseLib, true);
  ls.pop(1);
  ls.requireF("table", TableLib.openTableLib, true);
  ls.pop(1);
  ls.requireF("string", StringLib.openStringLib, true);
  ls.pop(1);
  ls.requireF("math", MathLib.openMathLib, true);
  ls.pop(1);

  // Register the single 'mal' table
  LuaMalBindings.register(ls, api: malApi);

  // Execute a test script using the Flat API
  const testScript = '''
print("Running test script...")

-- 1. Test Environment Variables
mal.setEnv("TEST_VAR", "Hello from Flat API")
local envResult = mal.getEnv("TEST_VAR")
print("getEnv TEST_VAR: " .. tostring(envResult))

-- 2. Test Key-Value Store
mal.setKey("UserScore", "42")
local scoreResult = mal.getKey("UserScore")
print("getKey UserScore: " .. tostring(scoreResult))

-- 3. Test Virtual File System
local testFile = "/test_mal.txt"
print("Writing to file: " .. testFile)
mal.fwrite(testFile, "This is VFS content via MAL!")

local fileExists = mal.fexists(testFile)
print("File exists: " .. tostring(fileExists))

local content = mal.fread(testFile)
print("File Content: " .. tostring(content))

print("Deleting file...")
mal.rm(testFile)

local existsAfterRm = mal.fexists(testFile)
print("File exists after rm: " .. tostring(existsAfterRm))

-- 4. Test Network Operations
print("Simulating sendText to channel 0 (Broadcast)...")
mal.sendText("Broadcast from Lua!", 0)

print("Simulating sendText to a specific node...")
mal.sendText("Directed message from Lua!", "010203040506")

print("Test complete.")
''';

  final result = ls.doString(testScript);
  final resultStr = result.toString();
  if (resultStr.contains('LUA_OK') ||
      resultStr == '0' ||
      (result as dynamic) == 0) {
    print("Script executed successfully.");
  } else {
    print("Script Execution failed. Code: $result");
  }
}

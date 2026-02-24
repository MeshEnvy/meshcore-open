import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/lua_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:meshcore_open/utils/app_logger.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.current.path;
  }
}

void main() {
  test('LuaService executes autoexec.lua', () async {
    PathProviderPlatform.instance = MockPathProviderPlatform();

    final driveDir = Directory('${Directory.current.path}/drive');
    if (!await driveDir.exists()) {
      await driveDir.create();
    }

    final autoexecFile = File('${driveDir.path}/autoexec.lua');
    await autoexecFile.writeAsString('print("hello from test script")');

    final luaService = LuaService();
    await luaService.initialize();

    // Clean up
    if (await autoexecFile.exists()) {
      await autoexecFile.delete();
    }
    await driveDir.delete();
  });
}

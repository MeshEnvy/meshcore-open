import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../utils/platform_info.dart';

void setupSqfliteFactory() {
  if (PlatformInfo.isDesktop) {
    sqfliteFfiInit();
    if (databaseFactory != databaseFactoryFfi) {
      databaseFactory = databaseFactoryFfi;
    }
  }
}

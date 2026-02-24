import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
void main() {
  if (kIsWeb) {
    BrowserContextMenu.disableContextMenu();
  }
}

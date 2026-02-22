// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class BrowserDetection {
  static bool get isChrome {
    final userAgent = html.window.navigator.userAgent.toLowerCase();
    final vendor = html.window.navigator.vendor.toLowerCase();
    
    // Chrome UA typically contains 'chrome' and vendor is 'Google Inc.'
    // This also excludes Firefox, Safari, and sometimes Edge/Brave depending on strictness.
    // For Web Bluetooth, Chrome, Edge (latest), and Brave usually work.
    // But we'll follow the user's request for "isChrome".
    return userAgent.contains('chrome') && vendor.contains('google');
  }
}

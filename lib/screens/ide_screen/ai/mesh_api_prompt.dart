import 'package:flutter/services.dart';

/// Loads and caches the Mesh API system prompt from the bundled Markdown file.
///
/// **To extend the API reference**, edit:
///   `assets/ai/mesh_api_reference.md`
///
/// The file is written in plain Markdown so it is easy to read, diff, and
/// grow alongside the Lua MAL bindings without touching any Dart code.
///
/// The prompt is loaded once at service init time and cached for the
/// lifetime of the app session.
class MeshApiPrompt {
  MeshApiPrompt._();

  static const String _assetPath = 'assets/ai/mesh_api_reference.md';

  static String? _cached;

  /// Returns the cached prompt. Call [load] during app/service init.
  /// Falls back to a minimal inline prompt if the asset failed to load.
  static String get systemPrompt => _cached ?? _fallbackPrompt;

  /// Loads the prompt from the asset bundle and caches it.
  /// Safe to call multiple times — subsequent calls are no-ops.
  static Future<void> load() async {
    if (_cached != null) return;
    try {
      _cached = await rootBundle.loadString(_assetPath);
    } catch (e) {
      // Asset missing or build not refreshed — fall back to inline stub.
      _cached = _fallbackPrompt;
    }
  }

  /// Minimal inline fallback in case the asset bundle is unavailable
  /// (e.g. during unit tests or a stale hot-reload without restart).
  static const String _fallbackPrompt = '''
You are a Lua 5.4 assistant for MeshCore. Scripts run in a sandboxed Lua VM.
The global `mal` table provides all host APIs:
  mal.getKnownNodes(), mal.getNode(id), mal.sendText(text, dest), mal.sendBytes(payload, port, dest)
  mal.setKey(k,v), mal.getKey(k), mal.setEnv(k,v), mal.getEnv(k)
  mal.fwrite(path, content), mal.fread(path), mal.mkdir(path), mal.rm(path)
Standard libs available: _G, string, table, math. NOT available: io, os, coroutine.
Never invent mal.* functions that are not listed above.
''';
}

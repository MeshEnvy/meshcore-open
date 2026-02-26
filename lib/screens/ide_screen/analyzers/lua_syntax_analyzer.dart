// ignore: implementation_imports
import 'package:lua_dardo/src/compiler/parser/parser.dart';

/// A single diagnostic returned by [LuaSyntaxAnalyzer].
class LuaDiagnostic {
  final int line; // 0-based line index
  final String message;

  const LuaDiagnostic({required this.line, required this.message});
}

/// Runs a fast synchronous Lua parse and returns any [LuaDiagnostic]s.
///
/// Decoupled from any editor library — just plain Dart.
class LuaSyntaxAnalyzer {
  const LuaSyntaxAnalyzer();

  static const _chunkName = 'script';

  List<LuaDiagnostic> analyze(String src) {
    if (src.trim().isEmpty) return const [];
    try {
      Parser.parse(src, _chunkName);
      return const [];
    } catch (e) {
      return [_parseError(e.toString())];
    }
  }

  /// Parses a lua_dardo exception string into a [LuaDiagnostic].
  ///
  /// Expected format: `Exception: script:<line>: <message>`
  static LuaDiagnostic _parseError(String raw) {
    String msg = raw.startsWith('Exception: ') ? raw.substring(11) : raw;

    final pattern = RegExp(r'^[^:]+:(\d+):\s*(.*)$');
    final match = pattern.firstMatch(msg);

    int line = 0;
    String description = msg;

    if (match != null) {
      final rawLine = int.tryParse(match.group(1) ?? '1') ?? 1;
      line = (rawLine - 1).clamp(0, 1 << 20);
      description = match.group(2) ?? msg;
    }

    return LuaDiagnostic(line: line, message: description);
  }
}

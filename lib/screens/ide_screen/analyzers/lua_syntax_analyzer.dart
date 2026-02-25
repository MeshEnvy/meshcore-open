import 'dart:async';

import 'package:flutter_code_editor/flutter_code_editor.dart';
// ignore: implementation_imports
import 'package:lua_dardo/src/compiler/parser/parser.dart';

/// Syntax-only Lua analyzer that reports parse errors as [Issue]s.
///
/// It calls [Parser.parse] from lua_dardo synchronously — the parser is
/// pure-Dart and fast enough that the slight async wrapper is just to satisfy
/// the [AbstractAnalyzer] contract without blocking the UI.
///
/// Error messages from lua_dardo follow the pattern:
///   `<chunkName>:<line>: <message>`
/// We strip the chunk-name prefix and extract the 1-based line number.
class LuaSyntaxAnalyzer extends AbstractAnalyzer {
  const LuaSyntaxAnalyzer();

  static const _chunkName = 'script';

  @override
  Future<AnalysisResult> analyze(Code code) async {
    final src = code.text;
    // Empty or whitespace-only files are always valid.
    if (src.trim().isEmpty) return const AnalysisResult(issues: []);

    try {
      Parser.parse(src, _chunkName);
      return const AnalysisResult(issues: []);
    } catch (e) {
      final issue = _parseError(e.toString());
      return AnalysisResult(issues: [issue]);
    }
  }

  /// Parses a lua_dardo exception string into an [Issue].
  ///
  /// Expected format: `Exception: script:<line>: <message>`
  static Issue _parseError(String raw) {
    // Strip the leading "Exception: " wrapper Dart adds.
    String msg = raw.startsWith('Exception: ') ? raw.substring(11) : raw;

    // Try to match `<chunkName>:<line>: <rest>`.
    final pattern = RegExp(r'^[^:]+:(\d+):\s*(.*)$');
    final match = pattern.firstMatch(msg);

    int line = 0; // 0-indexed for flutter_code_editor
    String description = msg;

    if (match != null) {
      final rawLine = int.tryParse(match.group(1) ?? '1') ?? 1;
      line = (rawLine - 1).clamp(0, 1 << 20);
      description = match.group(2) ?? msg;
    }

    return Issue(line: line, message: description, type: IssueType.error);
  }
}

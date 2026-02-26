import '../analyzers/lua_syntax_analyzer.dart';

/// Assembles a context-rich prompt from the current editor state.
///
/// Injected into every AI request so the model always knows what script
/// is open, what errors are present, and what the script printed last time
/// it ran — without the user needing to paste anything manually.
class AiContextBuilder {
  final String? fileName;
  final String? scriptContent;
  final List<LuaDiagnostic>? diagnostics;

  /// Lines from the most recent script run (stdout + errors).
  /// Capped to the last [_maxLogLines] to avoid flooding the context.
  final List<String>? logs;

  /// Text currently selected in the editor.
  /// When non-empty, injected as a ## Selected code section so references
  /// to "this" resolve to the highlighted region rather than the whole script.
  final String? selectedText;

  static const int _maxLogLines = 80;

  const AiContextBuilder({
    this.fileName,
    this.scriptContent,
    this.diagnostics,
    this.logs,
    this.selectedText,
  });

  /// Returns the full prompt to send to the model, merging the user's
  /// message with the current script context, diagnostics, and runtime output.
  String buildPrompt(String userMessage) {
    final sb = StringBuffer();

    if (fileName != null && scriptContent != null) {
      sb.writeln('## Current file: $fileName');
      sb.writeln('```lua');
      sb.writeln(scriptContent);
      sb.writeln('```');
      sb.writeln();
    }

    final diags = diagnostics;
    if (diags != null && diags.isNotEmpty) {
      sb.writeln('## Syntax errors');
      for (final d in diags) {
        sb.writeln('  - Line ${d.line + 1}: ${d.message}');
      }
      sb.writeln();
    }

    final logLines = logs;
    if (logLines != null && logLines.isNotEmpty) {
      sb.writeln('## Runtime output (last run)');
      sb.writeln('```');
      final omitted = logLines.length > _maxLogLines
          ? logLines.length - _maxLogLines
          : 0;
      if (omitted > 0) {
        sb.writeln('... ($omitted earlier lines omitted)');
      }
      final tail = omitted > 0 ? logLines.sublist(omitted) : logLines;
      for (final line in tail) {
        sb.writeln(line);
      }
      sb.writeln('```');
      sb.writeln();
    }

    final sel = selectedText;
    if (sel != null && sel.isNotEmpty) {
      sb.writeln('## Selected code (the user is referring to "this")');
      sb.writeln('```lua');
      sb.writeln(sel);
      sb.writeln('```');
      sb.writeln();
    }

    sb.writeln('## Request');
    sb.write(userMessage);

    return sb.toString();
  }

  /// Convenience factory for the common "fix errors" quick action.
  String buildFixErrorsPrompt() =>
      buildPrompt('Please fix all syntax errors and explain what was wrong.');

  /// Convenience factory for "explain" quick action.
  String buildExplainPrompt() =>
      buildPrompt('Explain what this script does, step by step.');

  /// Convenience factory for "add comments" quick action.
  String buildAddCommentsPrompt() => buildPrompt(
    'Add clear Lua comments to the script explaining each section. '
    'Return the full commented script.',
  );

  /// Convenience factory for "refactor" quick action.
  String buildRefactorPrompt() => buildPrompt(
    'Refactor this script to be cleaner and more idiomatic Lua. '
    'Return the full refactored script.',
  );
}

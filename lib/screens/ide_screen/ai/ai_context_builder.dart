import 'package:flutter_code_editor/flutter_code_editor.dart';

/// Assembles a context-rich prompt from the current editor state.
///
/// Injected into every AI request so the model always knows what script
/// is open and what errors are present — without the user needing to paste
/// anything manually.
class AiContextBuilder {
  final String? fileName;
  final String? scriptContent;
  final AnalysisResult? analysisResult;

  const AiContextBuilder({
    this.fileName,
    this.scriptContent,
    this.analysisResult,
  });

  /// Returns the full prompt to send to the model, merging the user's
  /// message with the current script context and diagnostic information.
  String buildPrompt(String userMessage) {
    final sb = StringBuffer();

    if (fileName != null && scriptContent != null) {
      sb.writeln('## Current file: $fileName');
      sb.writeln('```lua');
      sb.writeln(scriptContent);
      sb.writeln('```');
      sb.writeln();
    }

    final result = analysisResult;
    if (result != null && result.issues.isNotEmpty) {
      final errors = result.issues
          .where((i) => i.type == IssueType.error)
          .toList();
      final warnings = result.issues
          .where((i) => i.type == IssueType.warning)
          .toList();

      if (errors.isNotEmpty) {
        sb.writeln('## Syntax errors');
        for (final e in errors) {
          sb.writeln('  - Line ${e.line + 1}: ${e.message}');
        }
        sb.writeln();
      }

      if (warnings.isNotEmpty) {
        sb.writeln('## Warnings');
        for (final w in warnings) {
          sb.writeln('  - Line ${w.line + 1}: ${w.message}');
        }
        sb.writeln();
      }
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

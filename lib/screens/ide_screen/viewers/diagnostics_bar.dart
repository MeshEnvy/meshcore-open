import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

/// A compact status bar shown below the editor toolbar when Lua syntax
/// errors are present.  Shows an error-count badge and the first error
/// message; tapping it jumps to nothing (the gutter already marks the line).
class DiagnosticsBar extends StatelessWidget {
  final AnalysisResult analysisResult;

  const DiagnosticsBar({super.key, required this.analysisResult});

  @override
  Widget build(BuildContext context) {
    final errors = analysisResult.issues
        .where((i) => i.type == IssueType.error)
        .toList();
    final warnings = analysisResult.issues
        .where((i) => i.type == IssueType.warning)
        .toList();

    if (errors.isEmpty && warnings.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (errors.isNotEmpty) ...[
            _Badge(
              count: errors.length,
              icon: Icons.error_outline,
              color: const Color(0xFFf48771),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                errors.first.message,
                style: const TextStyle(
                  color: Color(0xFFf48771),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else if (warnings.isNotEmpty) ...[
            _Badge(
              count: warnings.length,
              icon: Icons.warning_amber_outlined,
              color: const Color(0xFFcca700),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                warnings.first.message,
                style: const TextStyle(
                  color: Color(0xFFcca700),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          // Line number hint
          if (errors.isNotEmpty)
            Text(
              'Line ${errors.first.line + 1}',
              style: const TextStyle(color: Color(0xFF888888), fontSize: 10),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  final IconData icon;
  final Color color;

  const _Badge({required this.count, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

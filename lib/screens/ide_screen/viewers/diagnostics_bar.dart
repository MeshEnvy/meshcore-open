import 'package:flutter/material.dart';

import '../analyzers/lua_syntax_analyzer.dart';

/// A compact status bar shown below the editor toolbar when Lua syntax
/// errors are present.  Shows an error-count badge and the first error
/// message.
class DiagnosticsBar extends StatelessWidget {
  final List<LuaDiagnostic> diagnostics;

  const DiagnosticsBar({super.key, required this.diagnostics});

  @override
  Widget build(BuildContext context) {
    if (diagnostics.isEmpty) return const SizedBox.shrink();

    final first = diagnostics.first;
    const color = Color(0xFFf48771);

    return Container(
      width: double.infinity,
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Badge(
            count: diagnostics.length,
            icon: Icons.error_outline,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              first.message,
              style: const TextStyle(
                color: color,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'Line ${first.line + 1}',
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

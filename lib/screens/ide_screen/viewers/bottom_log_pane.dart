import 'package:flutter/material.dart';

import '../../../services/lua_service.dart';

/// Persistent bottom split pane that shows all process logs in chronological
/// order.  Always visible; replaces the old "All Processes" right-pane view.
class BottomLogPane extends StatelessWidget {
  final ScrollController scrollController;
  final VoidCallback onClear;

  const BottomLogPane({
    super.key,
    required this.scrollController,
    required this.onClear,
  });

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Collects every log line from every process and sorts them chronologically.
  ///
  /// Each line is stored as `[HH:MM:SS.mmm] message` so we prefix the
  /// process name to get `[processName] [HH:MM:SS.mmm] message` then sort
  /// on the substring that starts at the first `] [`.
  List<String> _buildLogs() {
    final allLogs = <String>[];
    for (final p in LuaService().processes) {
      for (final log in p.logs) {
        allLogs.add('[${p.name}] $log');
      }
    }
    allLogs.sort((a, b) {
      final aIdx = a.indexOf('] [');
      final bIdx = b.indexOf('] [');
      final aTs = aIdx >= 0 ? a.substring(aIdx) : a;
      final bTs = bIdx >= 0 ? b.substring(bIdx) : b;
      return aTs.compareTo(bTs);
    });
    return allLogs;
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final logs = _buildLogs();

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Tab bar header ────────────────────────────────────────────────
          _LogTabBar(onClear: onClear),

          // ── Log output ────────────────────────────────────────────────────
          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Text(
                      'No output yet — run a script to see logs here',
                      style: TextStyle(color: Color(0xFF666666), fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    itemCount: logs.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: SelectableText(
                        logs[i],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFFD4D4D4),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _LogTabBar extends StatelessWidget {
  final VoidCallback onClear;
  const _LogTabBar({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      color: const Color(0xFF252525),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Active tab chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              border: Border(
                top: BorderSide(color: Colors.blueAccent.shade100, width: 1.5),
              ),
            ),
            child: const Text(
              'Logs',
              style: TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          // Clear button
          GestureDetector(
            onTap: onClear,
            child: const Tooltip(
              message: 'Clear logs',
              child: Icon(
                Icons.delete_sweep_outlined,
                color: Color(0xFF888888),
                size: 15,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

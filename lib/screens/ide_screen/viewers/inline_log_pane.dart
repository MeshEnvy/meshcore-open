import 'package:flutter/material.dart';

import '../../../services/lua_service.dart';
import '../ide_controller.dart';

/// Compact dark console pane shown below the code editor.
///
/// The caller is responsible for computing [logs] (history + current process)
/// and passing in the toolbar callbacks, keeping this widget fully stateless.
class InlineLogPane extends StatelessWidget {
  final IdeController ctrl;
  final ScrollController scrollController;
  final List<String> logs;
  final bool preserveHistory;
  final ValueChanged<bool?> onTogglePreserve;
  final VoidCallback onClear;

  const InlineLogPane({
    super.key,
    required this.ctrl,
    required this.scrollController,
    required this.logs,
    required this.preserveHistory,
    required this.onTogglePreserve,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final process =
        ctrl.inlineProcess ??
        (LuaService().processes.isNotEmpty
            ? LuaService().processes.last
            : null);

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Process header ────────────────────────────────────────────
          if (process != null) _ProcessHeader(process: process),

          // ── Log toolbar ───────────────────────────────────────────────
          _LogToolbar(
            preserveHistory: preserveHistory,
            onTogglePreserve: onTogglePreserve,
            onClear: onClear,
          ),

          // ── Log lines ─────────────────────────────────────────────────
          Expanded(
            child: process == null
                ? const Center(
                    child: Text(
                      'No processes yet — press ▶ to run a script',
                      style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                    ),
                  )
                : logs.isEmpty
                ? const Center(
                    child: Text(
                      'No output yet',
                      style: TextStyle(color: Color(0xFF666666), fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
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

class _ProcessHeader extends StatelessWidget {
  final LuaProcess process;
  const _ProcessHeader({required this.process});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(process);
    return Container(
      height: 28,
      color: const Color(0xFF2D2D2D),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(_statusIcon(process), color: color, size: 12),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              process.name,
              style: const TextStyle(
                color: Color(0xFFD4D4D4),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            process.status.name,
            style: TextStyle(color: color, fontSize: 10),
          ),
          const SizedBox(width: 8),
          if (process.status == LuaProcessStatus.running)
            GestureDetector(
              onTap: process.kill,
              child: const Tooltip(
                message: 'Kill process',
                child: Icon(Icons.stop, color: Colors.red, size: 14),
              ),
            ),
        ],
      ),
    );
  }

  IconData _statusIcon(LuaProcess p) => switch (p.status) {
    LuaProcessStatus.running => Icons.play_circle_fill,
    LuaProcessStatus.completed => Icons.check_circle,
    LuaProcessStatus.error => Icons.error,
    LuaProcessStatus.killed => Icons.stop_circle,
  };

  Color _statusColor(LuaProcess p) => switch (p.status) {
    LuaProcessStatus.running => Colors.green,
    LuaProcessStatus.completed => Colors.grey,
    LuaProcessStatus.error => Colors.red,
    LuaProcessStatus.killed => Colors.orange,
  };
}

class _LogToolbar extends StatelessWidget {
  final bool preserveHistory;
  final ValueChanged<bool?> onTogglePreserve;
  final VoidCallback onClear;

  const _LogToolbar({
    required this.preserveHistory,
    required this.onTogglePreserve,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      color: const Color(0xFF252525),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: Checkbox(
              value: preserveHistory,
              onChanged: onTogglePreserve,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: Color(0xFF666666)),
              activeColor: const Color(0xFF569CD6),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Preserve history',
            style: TextStyle(color: Color(0xFF888888), fontSize: 11),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onClear,
            child: const Tooltip(
              message: 'Clear log',
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

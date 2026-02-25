import 'package:flutter/material.dart';

import '../../../services/lua_service.dart';
import '../ide_controller.dart';

/// Right-pane dark console for process logs.
class IdeLogViewer extends StatelessWidget {
  final IdeController ctrl;
  const IdeLogViewer({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final List<String> logs;
    final String title;

    if (ctrl.showAllProcesses) {
      title = 'All Processes';
      final allLogs = <String>[];
      for (final p in LuaService().processes) {
        for (final log in p.logs) {
          allLogs.add('[${p.name}] $log');
        }
      }
      // Sort by the timestamp that LuaProcess.addLog embeds in each entry.
      // Each entry is formatted as "[processName] [HH:MM:SS.mmm] message",
      // so the timestamp starts after the first "] [" sequence.
      allLogs.sort((a, b) {
        final aIdx = a.indexOf('] [');
        final bIdx = b.indexOf('] [');
        final aTs = aIdx >= 0 ? a.substring(aIdx) : a;
        final bTs = bIdx >= 0 ? b.substring(bIdx) : b;
        return aTs.compareTo(bTs);
      });
      logs = allLogs;
    } else if (ctrl.selectedProcess != null) {
      title = '${ctrl.selectedProcess!.name} Logs';
      logs = ctrl.selectedProcess!.logs;
    } else {
      return const Center(child: Text('No process selected'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF1E1E1E),
            child: ListView.builder(
              controller: ctrl.logScrollController,
              padding: const EdgeInsets.all(8),
              itemCount: logs.length,
              itemBuilder: (_, index) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: SelectableText(
                  logs[index],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Color(0xFFD4D4D4),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

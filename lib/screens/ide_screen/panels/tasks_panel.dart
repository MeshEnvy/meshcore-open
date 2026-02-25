import 'package:flutter/material.dart';

import '../../../services/lua_service.dart';
import '../ide_controller.dart';

/// Left-pane tasks list for the Tasks tab.
class IdeTasksPanel extends StatelessWidget {
  final IdeController ctrl;
  const IdeTasksPanel({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final processes = LuaService().processes
        .where((p) => p.status == LuaProcessStatus.running)
        .toList()
        .reversed
        .toList();

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.list_alt),
            title: const Text(
              'All Processes',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            selected: ctrl.showAllProcesses,
            selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
            onTap: () => ctrl.selectProcess(null, showAll: true),
          ),
          const Divider(height: 1),
          Expanded(
            child: processes.isEmpty
                ? const Center(child: Text('No tasks'))
                : ListView.builder(
                    itemCount: processes.length,
                    itemBuilder: (ctx, index) {
                      final process = processes[index];
                      final isSelected =
                          !ctrl.showAllProcesses &&
                          ctrl.selectedProcess?.id == process.id;

                      final (
                        Color statusColor,
                        IconData statusIcon,
                      ) = switch (process.status) {
                        LuaProcessStatus.running => (
                          Colors.green,
                          Icons.play_circle_fill,
                        ),
                        LuaProcessStatus.completed => (
                          Colors.grey,
                          Icons.check_circle,
                        ),
                        LuaProcessStatus.error => (Colors.red, Icons.error),
                        LuaProcessStatus.killed => (
                          Colors.orange,
                          Icons.stop_circle,
                        ),
                      };

                      return ListTile(
                        leading: Icon(statusIcon, color: statusColor, size: 20),
                        title: Text(
                          process.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          process.status.name,
                          style: TextStyle(fontSize: 10, color: statusColor),
                        ),
                        selected: isSelected,
                        selectedTileColor: Theme.of(
                          ctx,
                        ).colorScheme.primaryContainer,
                        onTap: () => ctrl.selectProcess(process),
                        trailing: process.status == LuaProcessStatus.running
                            ? IconButton(
                                icon: const Icon(Icons.stop, color: Colors.red),
                                tooltip: 'Kill',
                                onPressed: () {
                                  process.kill();
                                  // Notify LuaService listeners (including
                                  // IdeScreen) so the toolbar/status updates.
                                  LuaService().notify();
                                },
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

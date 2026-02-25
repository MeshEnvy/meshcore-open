import 'package:flutter/material.dart';

import '../ide_controller.dart';

/// Left-pane env-var list for the Env tab.
class IdeEnvPanel extends StatelessWidget {
  final IdeController ctrl;
  const IdeEnvPanel({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    if (ctrl.isLoadingEnv) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition, null),
        child: ctrl.envVars.isEmpty
            ? const Center(child: Text('No environment variables found'))
            : ListView.builder(
                itemCount: ctrl.envVars.length,
                itemBuilder: (ctx, index) {
                  final envVar = ctrl.envVars[index];
                  final isSelected = ctrl.selectedEnvKey == envVar.key;
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onSecondaryTapDown: (details) => _showContextMenu(
                      ctx,
                      details.globalPosition,
                      envVar.key,
                    ),
                    child: ListTile(
                      title: Text(envVar.key),
                      selected: isSelected,
                      selectedTileColor: Theme.of(
                        ctx,
                      ).colorScheme.primaryContainer,
                      onTap: () => ctrl.selectEnvVar(envVar.key, envVar.value),
                    ),
                  );
                },
              ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position, String? envKey) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(
          value: 'secret',
          child: Row(
            children: [
              Icon(Icons.vpn_key_outlined, size: 20),
              SizedBox(width: 8),
              Text('Add Variable'),
            ],
          ),
        ),
        if (envKey != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 20, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ],
    ).then((value) async {
      if (!context.mounted) return;
      if (value == 'secret') {
        await _showCreateDialog(context);
      } else if (value == 'delete' && envKey != null) {
        await ctrl.deleteEnvVar(envKey, context);
      }
    });
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final keyController = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Variable'),
        content: TextField(
          controller: keyController,
          decoration: const InputDecoration(
            labelText: 'Key',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, keyController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (key != null && key.isNotEmpty && context.mounted) {
      await ctrl.createEnvVar(key, context);
    }
  }
}

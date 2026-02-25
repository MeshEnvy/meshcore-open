import 'package:flutter/material.dart';

/// Toolbar for the code editor pane.
///
/// All actions are passed in as callbacks so this widget stays pure/stateless.
class IdeEditorToolbar extends StatelessWidget {
  final bool isLua;
  final bool hasUnsavedChanges;
  final bool logPaneOpen;
  final bool aiPaneOpen;
  final VoidCallback? onRun;
  final VoidCallback? onSave;
  final VoidCallback onToggleLog;
  final VoidCallback onToggleAi;

  const IdeEditorToolbar({
    super.key,
    required this.isLua,
    required this.hasUnsavedChanges,
    required this.logPaneOpen,
    required this.aiPaneOpen,
    this.onRun,
    this.onSave,
    required this.onToggleLog,
    required this.onToggleAi,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 36,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          // Run (Lua only)
          if (isLua)
            IconButton(
              icon: Icon(Icons.play_arrow, color: scheme.primary),
              tooltip: 'Run Script',
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: onRun,
            ),

          // Save
          IconButton(
            icon: const Icon(Icons.save, size: 18),
            tooltip: 'Save',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onSave,
          ),

          // Log pane toggle
          IconButton(
            icon: Icon(
              Icons.terminal,
              size: 18,
              color: logPaneOpen ? scheme.primary : null,
            ),
            tooltip: logPaneOpen ? 'Hide Log' : 'Show Log',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onToggleLog,
          ),

          // AI pane toggle
          IconButton(
            icon: Icon(
              Icons.auto_awesome,
              size: 17,
              color: aiPaneOpen ? scheme.primary : null,
            ),
            tooltip: aiPaneOpen ? 'Hide AI Assistant' : 'Show AI Assistant',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onToggleAi,
          ),

          // Unsaved indicator
          if (hasUnsavedChanges)
            Expanded(
              child: Text(
                'Unsaved changes',
                style: TextStyle(color: scheme.error, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

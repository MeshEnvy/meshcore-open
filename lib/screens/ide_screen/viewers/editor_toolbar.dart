import 'package:flutter/material.dart';

/// Toolbar for the code editor pane.
///
/// All actions are passed in as callbacks so this widget stays pure/stateless.
///
/// When [isRunning] is true the play button is replaced with a red stop (■)
/// button that fires [onStop].  This happens when the script has registered
/// event listeners and is staying resident so the user knows how to kill it.
class IdeEditorToolbar extends StatelessWidget {
  final bool isLua;
  final bool hasUnsavedChanges;
  final bool aiPaneOpen;

  /// True when the inline process is alive (running or resident daemon).
  final bool isRunning;

  final VoidCallback? onRun;
  final VoidCallback? onStop;
  final VoidCallback? onSave;
  final VoidCallback onToggleAi;

  const IdeEditorToolbar({
    super.key,
    required this.isLua,
    required this.hasUnsavedChanges,
    required this.aiPaneOpen,
    this.isRunning = false,
    this.onRun,
    this.onStop,
    this.onSave,
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
          // Run / Stop  (Lua only)
          if (isLua)
            if (isRunning)
              IconButton(
                icon: Icon(Icons.stop, color: scheme.error),
                tooltip: 'Stop Script',
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onStop,
              )
            else
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

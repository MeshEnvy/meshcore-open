import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:provider/provider.dart';

import '../../../services/lua_service.dart';
import '../../../services/mal/mal_api.dart';
import '../ide_controller.dart';

/// Right-pane code editor with a thin toolbar.
class IdeCodeEditor extends StatelessWidget {
  final IdeController ctrl;
  const IdeCodeEditor({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final controller = ctrl.codeController!;
    final isLua =
        ctrl.selectedFile?.path.toLowerCase().endsWith('.lua') == true;

    return Column(
      children: [
        // Toolbar
        Container(
          height: 36,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              if (isLua)
                IconButton(
                  icon: Icon(
                    Icons.play_arrow,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  tooltip: 'Run Script',
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () async {
                    final file = ctrl.selectedFile;
                    if (file == null) return;
                    if (!context.mounted) return;
                    final malApi = context.read<MalApi>();
                    await LuaService().runScript(
                      malApi,
                      controller.text,
                      name: file.path.split('/').last,
                    );
                    await ctrl.selectProcess(null, showAll: false);
                  },
                ),
              IconButton(
                icon: const Icon(Icons.save, size: 18),
                tooltip: 'Save',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: ctrl.hasUnsavedChanges
                    ? () => ctrl.saveCurrentFile(context)
                    : null,
              ),
              if (ctrl.hasUnsavedChanges)
                Expanded(
                  child: Text(
                    'Unsaved changes',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: CodeTheme(
            data: CodeThemeData(styles: monokaiSublimeTheme),
            child: CodeField(
              controller: controller,
              expands: true,
              textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

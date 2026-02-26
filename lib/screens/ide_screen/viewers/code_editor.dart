import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:provider/provider.dart';

import '../../../services/lua_service.dart';
import '../../../services/mal/mal_api.dart';
import '../ai/ai_assistant_pane.dart';
import '../ide_controller.dart';
import '../widgets/resize_handle.dart';
import 'diagnostics_bar.dart';
import 'editor_toolbar.dart';
import 'inactive_selection_overlay.dart';

/// Right-pane code editor with an optional resizable AI assistant pane.
class IdeCodeEditor extends StatefulWidget {
  final IdeController ctrl;
  const IdeCodeEditor({super.key, required this.ctrl});

  @override
  State<IdeCodeEditor> createState() => _IdeCodeEditorState();
}

class _IdeCodeEditorState extends State<IdeCodeEditor> {
  // ── AI pane visibility & size ─────────────────────────────────────────────
  bool _aiOpen = false;
  double _aiPaneWidth = 320;

  // ── Editor focus ──────────────────────────────────────────────────────────
  /// Dedicated focus node for the CodeField so we can restore focus (and
  /// therefore the selection highlight) after toolbar button presses.
  final FocusNode _editorFocusNode = FocusNode();

  IdeController get ctrl => widget.ctrl;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _editorFocusNode.dispose();
    super.dispose();
  }

  /// Returns focus to the code editor on the next frame so the selection
  /// highlight survives toolbar button clicks (which temporarily steal focus).
  void _restoreFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editorFocusNode.requestFocus();
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _onRun() async {
    final file = ctrl.selectedFile;
    if (file == null || ctrl.codeController == null) return;
    if (!mounted) return;
    final malApi = context.read<MalApi>();

    await LuaService().runScript(
      malApi,
      ctrl.codeController!.text,
      name: file.path.split('/').last,
    );

    ctrl.inlineProcess = LuaService().processes.last;
    ctrl.notify();
    _restoreFocus();
  }

  void _onStop() {
    final process = ctrl.inlineProcess;
    if (process == null) return;
    process.kill();
    ctrl.notify();
    _restoreFocus();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final controller = ctrl.codeController!;
    final isLua =
        ctrl.selectedFile?.path.toLowerCase().endsWith('.lua') == true;

    return Row(
      children: [
        // ── Editor column ──────────────────────────────────────────────────
        Expanded(
          child: Column(
            children: [
              // ── Toolbar ─────────────────────────────────────────────────
              IdeEditorToolbar(
                isLua: isLua,
                hasUnsavedChanges: ctrl.hasUnsavedChanges,
                aiPaneOpen: _aiOpen,
                isRunning:
                    ctrl.inlineProcess?.status == LuaProcessStatus.running,
                onRun: _onRun,
                onStop: _onStop,
                onSave: ctrl.hasUnsavedChanges
                    ? () {
                        ctrl.saveCurrentFile(context);
                        _restoreFocus();
                      }
                    : null,
                onToggleAi: () {
                  setState(() => _aiOpen = !_aiOpen);
                  _restoreFocus();
                },
              ),
              const Divider(height: 1),

              // ── Diagnostics bar (Lua only) ───────────────────────────────
              if (isLua)
                AnimatedBuilder(
                  animation: controller,
                  builder: (_, child) =>
                      DiagnosticsBar(analysisResult: controller.analysisResult),
                ),

              // ── Code editor ─────────────────────────────────────────────
              Expanded(
                child: InactiveSelectionOverlay(
                  controller: controller,
                  editorFocusNode: _editorFocusNode,
                  child: CodeTheme(
                    data: CodeThemeData(styles: monokaiSublimeTheme),
                    child: CodeField(
                      controller: controller,
                      focusNode: _editorFocusNode,
                      expands: true,
                      textStyle: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── AI assistant pane (resizable) ──────────────────────────────────
        if (_aiOpen) ...[
          // ExcludeFocus: pointer events in the resize handle must not steal
          // focus from the editor.
          ExcludeFocus(
            child: HorizontalResizeHandle(
              onDrag: (dx) => setState(() {
                _aiPaneWidth = (_aiPaneWidth - dx).clamp(240.0, 520.0);
              }),
            ),
          ),
          SizedBox(
            width: _aiPaneWidth,
            child: AiAssistantPane(ctrl: ctrl),
          ),
        ],
      ],
    );
  }
}

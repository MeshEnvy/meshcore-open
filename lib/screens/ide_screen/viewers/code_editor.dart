import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/styles/monokai-sublime.dart';

import '../../../services/lua_service.dart';
import '../../../services/mal/mal_api.dart';
import '../ai/ai_assistant_pane.dart';
import '../analyzers/lua_syntax_analyzer.dart';
import '../ide_controller.dart';
import '../widgets/resize_handle.dart';
import 'diagnostics_bar.dart';
import 'editor_toolbar.dart';

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

  // ── Lua diagnostics ───────────────────────────────────────────────────────
  final _analyzer = const LuaSyntaxAnalyzer();
  List<LuaDiagnostic> _diagnostics = const [];

  IdeController get ctrl => widget.ctrl;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _attachListener();
  }

  @override
  void didUpdateWidget(IdeCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ctrl.codeController != ctrl.codeController) {
      oldWidget.ctrl.codeController?.removeListener(_onCodeChanged);
      _attachListener();
    }
  }

  void _attachListener() {
    _diagnostics = const [];
    ctrl.codeController?.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    ctrl.codeController?.removeListener(_onCodeChanged);
    super.dispose();
  }

  void _onCodeChanged() {
    final text = ctrl.codeController?.text ?? '';
    final isLua =
        ctrl.selectedFile?.path.toLowerCase().endsWith('.lua') == true;

    final newDiags = isLua ? _analyzer.analyze(text) : <LuaDiagnostic>[];

    if (mounted) {
      setState(() => _diagnostics = newDiags);
    }
    ctrl.diagnostics = newDiags;
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
  }

  void _onStop() {
    final process = ctrl.inlineProcess;
    if (process == null) return;
    process.kill();
    ctrl.notify();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final controller = ctrl.codeController!;
    final isLua =
        ctrl.selectedFile?.path.toLowerCase().endsWith('.lua') == true;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (ctrl.hasUnsavedChanges) {
            ctrl.saveCurrentFile(context);
          }
        },
      },
      child: Row(
        children: [
          // ── Editor column ────────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // ── Toolbar ───────────────────────────────────────────────
                IdeEditorToolbar(
                  isLua: isLua,
                  hasUnsavedChanges: ctrl.hasUnsavedChanges,
                  aiPaneOpen: _aiOpen,
                  isRunning:
                      ctrl.inlineProcess?.status == LuaProcessStatus.running,
                  onRun: _onRun,
                  onStop: _onStop,
                  onSave: ctrl.hasUnsavedChanges
                      ? () => ctrl.saveCurrentFile(context)
                      : null,
                  onToggleAi: () => setState(() => _aiOpen = !_aiOpen),
                ),
                const Divider(height: 1),

                // ── Diagnostics bar (Lua only) ─────────────────────────────
                if (isLua) DiagnosticsBar(diagnostics: _diagnostics),

                // ── Code editor ───────────────────────────────────────────
                Expanded(
                  child: CodeEditor(
                    controller: controller,
                    wordWrap: true,
                    style: CodeEditorStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                      codeTheme: CodeHighlightTheme(
                        languages: {
                          'lua': CodeHighlightThemeMode(mode: langLua),
                        },
                        theme: monokaiSublimeTheme,
                      ),
                    ),
                    indicatorBuilder:
                        (
                          context,
                          editingController,
                          chunkController,
                          notifier,
                        ) {
                          return Row(
                            children: [
                              DefaultCodeLineNumber(
                                controller: editingController,
                                notifier: notifier,
                              ),
                              DefaultCodeChunkIndicator(
                                width: 20,
                                controller: chunkController,
                                notifier: notifier,
                              ),
                            ],
                          );
                        },
                    toolbarController: const _ContextMenuController(),
                  ),
                ),
              ],
            ),
          ),

          // ── AI assistant pane (resizable) ──────────────────────────────
          if (_aiOpen) ...[
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
      ),
    );
  }
}

// ── Minimal desktop context menu controller ──────────────────────────────────

/// No-op context menu; desktop OS provides its own right-click cut/copy/paste.
class _ContextMenuController implements SelectionToolbarController {
  const _ContextMenuController();

  @override
  void hide(BuildContext context) {}

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {}
}

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
import 'inline_log_pane.dart';

/// Right-pane code editor with an optional resizable inline log pane.
class IdeCodeEditor extends StatefulWidget {
  final IdeController ctrl;
  const IdeCodeEditor({super.key, required this.ctrl});

  @override
  State<IdeCodeEditor> createState() => _IdeCodeEditorState();
}

class _IdeCodeEditorState extends State<IdeCodeEditor> {
  // ── Log pane visibility & size ────────────────────────────────────────────
  bool _logOpen = false;
  double _logPaneHeight = 200;
  final ScrollController _logScrollController = ScrollController();

  // ── AI pane visibility & size ─────────────────────────────────────────────
  bool _aiOpen = false;
  double _aiPaneWidth = 320;

  // ── Editor focus ──────────────────────────────────────────────────────────
  /// Dedicated focus node for the CodeField so we can restore focus (and
  /// therefore the selection highlight) after toolbar button presses.
  final FocusNode _editorFocusNode = FocusNode();

  // ── History management ────────────────────────────────────────────────────
  /// Lines captured from previous runs when Preserve History is on.
  final List<String> _historicalLogs = [];

  /// How many lines at the start of the current process to skip (after Clear).
  int _logClearOffset = 0;

  bool _preserveHistory = false;

  IdeController get ctrl => widget.ctrl;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    ctrl.addListener(_onCtrlUpdate);
  }

  @override
  void dispose() {
    ctrl.removeListener(_onCtrlUpdate);
    _logScrollController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  void _onCtrlUpdate() {
    if (mounted && _logOpen) _scrollLogToBottom();
  }

  /// Returns focus to the code editor on the next frame so the selection
  /// highlight survives toolbar button clicks (which temporarily steal focus).
  void _restoreFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editorFocusNode.requestFocus();
    });
  }

  // ── Computed log list ─────────────────────────────────────────────────────

  /// Merges historical lines with the visible slice of the current process.
  List<String> get _effectiveLogs {
    final rawLogs = ctrl.inlineProcess?.logs ?? [];
    final offset = _logClearOffset.clamp(0, rawLogs.length);
    final visibleLines = rawLogs.sublist(offset);
    return [..._historicalLogs, ...visibleLines];
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _onRun() async {
    final file = ctrl.selectedFile;
    if (file == null || ctrl.codeController == null) return;
    if (!mounted) return;
    final malApi = context.read<MalApi>();

    // Preserve logs from the previous run before starting a new one.
    if (_preserveHistory && ctrl.inlineProcess != null) {
      final prevLogs = ctrl.inlineProcess!.logs;
      final offset = _logClearOffset.clamp(0, prevLogs.length);
      _historicalLogs.addAll(prevLogs.sublist(offset));
      if (_historicalLogs.isNotEmpty) {
        _historicalLogs.add('─' * 40); // visual separator between runs
      }
    }

    await LuaService().runScript(
      malApi,
      ctrl.codeController!.text,
      name: file.path.split('/').last,
    );

    // Attach the freshly-started process and reset the clear offset.
    if (LuaService().processes.isNotEmpty) {
      ctrl.inlineProcess = LuaService().processes.last;
      ctrl.notify();
    }
    _logClearOffset = 0;

    if (!_logOpen) setState(() => _logOpen = true);
    _scrollLogToBottom();
    // Running a script opens the log pane which may steal focus — restore it.
    _restoreFocus();
  }

  void _onStop() {
    final process = ctrl.inlineProcess;
    if (process == null) return;
    process.kill();
    ctrl.notify();
    _restoreFocus();
  }

  void _onClear() {
    setState(() {
      _historicalLogs.clear();
      _logClearOffset = ctrl.inlineProcess?.logs.length ?? 0;
    });
  }

  void _scrollLogToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        final pos = _logScrollController.position;
        if (pos.pixels >= pos.maxScrollExtent - 80) {
          _logScrollController.jumpTo(pos.maxScrollExtent);
        }
      }
    });
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
                logPaneOpen: _logOpen,
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
                onToggleLog: () {
                  setState(() => _logOpen = !_logOpen);
                  _restoreFocus();
                },
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

              // ── Resizable log pane ───────────────────────────────────────
              if (_logOpen) ...[
                VerticalResizeHandle(
                  onDrag: (dy) => setState(() {
                    _logPaneHeight = (_logPaneHeight - dy).clamp(80.0, 600.0);
                  }),
                ),
                SizedBox(
                  height: _logPaneHeight,
                  child: InlineLogPane(
                    ctrl: ctrl,
                    scrollController: _logScrollController,
                    logs: _effectiveLogs,
                    preserveHistory: _preserveHistory,
                    onTogglePreserve: (v) =>
                        setState(() => _preserveHistory = v ?? false),
                    onClear: _onClear,
                  ),
                ),
              ],
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

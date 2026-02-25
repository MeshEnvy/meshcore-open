import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:provider/provider.dart';

import '../../../services/lua_service.dart';
import '../../../services/mal/mal_api.dart';
import '../ide_controller.dart';
import '../widgets/resize_handle.dart';
import 'editor_toolbar.dart';
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
    super.dispose();
  }

  void _onCtrlUpdate() {
    if (mounted && _logOpen) _scrollLogToBottom();
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

    return Column(
      children: [
        // ── Toolbar ───────────────────────────────────────────────────────
        IdeEditorToolbar(
          isLua: isLua,
          hasUnsavedChanges: ctrl.hasUnsavedChanges,
          logPaneOpen: _logOpen,
          onRun: _onRun,
          onSave: ctrl.hasUnsavedChanges
              ? () => ctrl.saveCurrentFile(context)
              : null,
          onToggleLog: () => setState(() => _logOpen = !_logOpen),
        ),
        const Divider(height: 1),

        // ── Code editor ───────────────────────────────────────────────────
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

        // ── Resizable log pane ────────────────────────────────────────────
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
    );
  }
}

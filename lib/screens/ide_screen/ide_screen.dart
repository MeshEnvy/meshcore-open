import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../services/lua_service.dart';
import 'ide_controller.dart';
import 'panels/env_panel.dart';
import 'panels/file_panel.dart';
import 'panels/tasks_panel.dart';
import 'viewers/bottom_log_pane.dart';
import 'viewers/file_viewer.dart';
import 'widgets/resize_handle.dart';

export 'ide_controller.dart' show FileDisplayMode;

class IdeScreen extends StatefulWidget {
  const IdeScreen({super.key});

  @override
  State<IdeScreen> createState() => _IdeScreenState();
}

class _IdeScreenState extends State<IdeScreen> {
  late final IdeController _ctrl;

  // ── Layout ──────────────────────────────────────────────────────────────────
  double _sidePaneWidth = 260;
  double _logPaneHeight = 180;

  // ── Log pane state ──────────────────────────────────────────────────────────
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (kIsWeb) BrowserContextMenu.disableContextMenu();
    _ctrl = IdeController(context);
    _ctrl.addListener(_onCtrlUpdated);
    LuaService().addListener(_onLuaUpdated);
    _ctrl.init();
  }

  void _onCtrlUpdated() {
    if (mounted) setState(() {});
  }

  void _onLuaUpdated() {
    _ctrl.onLuaServiceUpdated();
    // Auto-scroll the bottom log pane to the newest entry if already near the
    // bottom (same heuristic used by the inline log pane).
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollController.hasClients) {
          final pos = _logScrollController.position;
          if (pos.pixels >= pos.maxScrollExtent - 100) {
            _logScrollController.jumpTo(pos.maxScrollExtent);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    if (kIsWeb) BrowserContextMenu.enableContextMenu();
    LuaService().removeListener(_onLuaUpdated);
    _ctrl.removeListener(_onCtrlUpdated);
    _logScrollController.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            ctrl.saveCurrentFile(context),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            ctrl.saveCurrentFile(context),
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: !ctrl.hasUnsavedChanges,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final shouldPop = await ctrl.promptDiscardChanges(context);
            if (shouldPop && mounted) {
              setState(() => ctrl.hasUnsavedChanges = false);
              if (context.mounted && Navigator.canPop(context)) {
                Navigator.pop(context, result);
              }
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                '${context.l10n.appSettings_ide}'
                '${ctrl.hasUnsavedChanges ? '*' : ''}',
              ),
              actions: const [],
            ),
            body: ctrl.isLoading
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      // ── Left pane (resizable) ─────────────────────────────
                      SizedBox(
                        width: _sidePaneWidth,
                        child: DefaultTabController(
                          length: 3,
                          child: Column(
                            children: [
                              TabBar(
                                tabs: [
                                  const Tab(text: 'Files'),
                                  Tab(text: context.l10n.ide_tasksTab),
                                  const Tab(text: 'Env'),
                                ],
                              ),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    IdeFilePanel(ctrl: ctrl),
                                    IdeTasksPanel(ctrl: ctrl),
                                    IdeEnvPanel(ctrl: ctrl),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Drag handle ───────────────────────────────────────
                      HorizontalResizeHandle(
                        onDrag: (dx) => setState(() {
                          _sidePaneWidth = (_sidePaneWidth + dx).clamp(
                            150.0,
                            600.0,
                          );
                        }),
                      ),

                      // ── Right column: editor + bottom log split ───────────
                      Expanded(
                        child: Column(
                          children: [
                            // ── Main editor / viewer area ─────────────────
                            Expanded(
                              child:
                                  (ctrl.selectedFile == null &&
                                      ctrl.selectedEnvKey == null &&
                                      ctrl.displayMode !=
                                          FileDisplayMode.processLogs)
                                  ? const Center(
                                      child: Text(
                                        'Select a file or env var to edit',
                                      ),
                                    )
                                  : IdeFileViewer(ctrl: ctrl),
                            ),

                            // ── Resize handle between editor and log ──────
                            VerticalResizeHandle(
                              onDrag: (dy) => setState(() {
                                _logPaneHeight = (_logPaneHeight - dy).clamp(
                                  60.0,
                                  600.0,
                                );
                              }),
                            ),

                            // ── Bottom log pane ───────────────────────────
                            SizedBox(
                              height: _logPaneHeight,
                              child: BottomLogPane(
                                scrollController: _logScrollController,
                                onClear: _clearLogs,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  void _clearLogs() {
    for (final p in LuaService().processes) {
      p.logs.clear();
    }
    setState(() {});
  }
}

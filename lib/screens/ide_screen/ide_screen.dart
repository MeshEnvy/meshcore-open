import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../services/lua_service.dart';
import 'ide_controller.dart';
import 'panels/env_panel.dart';
import 'panels/file_panel.dart';
import 'panels/tasks_panel.dart';
import 'viewers/file_viewer.dart';

export 'ide_controller.dart' show FileDisplayMode;

class IdeScreen extends StatefulWidget {
  const IdeScreen({super.key});

  @override
  State<IdeScreen> createState() => _IdeScreenState();
}

class _IdeScreenState extends State<IdeScreen> {
  late final IdeController _ctrl;

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
  }

  @override
  void dispose() {
    if (kIsWeb) BrowserContextMenu.enableContextMenu();
    LuaService().removeListener(_onLuaUpdated);
    _ctrl.removeListener(_onCtrlUpdated);
    _ctrl.dispose();
    super.dispose();
  }

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
                      // ── Left pane ───────────────────────────────────────
                      Expanded(
                        flex: 1,
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
                      // ── Right pane ──────────────────────────────────────
                      Expanded(
                        flex: 2,
                        child:
                            (ctrl.selectedFile == null &&
                                ctrl.selectedEnvKey == null &&
                                ctrl.displayMode != FileDisplayMode.processLogs)
                            ? const Center(
                                child: Text('Select a file or env var to edit'),
                              )
                            : IdeFileViewer(ctrl: ctrl),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/mal/mal_api.dart';
import '../ide_controller.dart';
import 'ai_assistant_service.dart';
import 'ai_chat_view.dart';
import 'ai_context_builder.dart';
import 'ai_preferences_panel.dart';
import 'ai_setup_view.dart';

/// The right-side AI assistant pane.
///
/// Picks between [AiSetupView] (Ollama not detected) and [AiChatView]
/// (connected), with an inline preferences drawer toggled by the ⚙ button.
class AiAssistantPane extends StatefulWidget {
  final IdeController ctrl;

  const AiAssistantPane({super.key, required this.ctrl});

  @override
  State<AiAssistantPane> createState() => _AiAssistantPaneState();
}

class _AiAssistantPaneState extends State<AiAssistantPane> {
  late final AiAssistantService _svc;
  bool _showPreferences = false;
  bool _initialized = false;

  IdeController get ctrl => widget.ctrl;

  @override
  void initState() {
    super.initState();
    _svc = AiAssistantService();
    _svc.addListener(_onSvcUpdate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final malApi = context.read<MalApi>();
      _svc.init(malApi).then((_) {
        // Auto-probe on first open so connected users see the chat immediately.
        _svc.testConnection();
      });
    }
  }

  @override
  void dispose() {
    _svc.removeListener(_onSvcUpdate);
    _svc.dispose();
    super.dispose();
  }

  void _onSvcUpdate() {
    if (mounted) setState(() {});
  }

  // ── Context builder from current editor state ──────────────────────────────

  AiContextBuilder get _contextBuilder {
    final file = ctrl.selectedFile;
    final code = ctrl.codeController;
    return AiContextBuilder(
      fileName: file?.path.split('/').last,
      scriptContent: code?.text,
      analysisResult: code?.analysisResult,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final svc = _svc;

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        children: [
          // ── Pane header ──────────────────────────────────────────────────
          _PaneHeader(
            service: svc,
            showPreferences: _showPreferences,
            onTogglePreferences: () =>
                setState(() => _showPreferences = !_showPreferences),
            onClearHistory: svc.isConnected ? svc.clearHistory : null,
          ),

          const Divider(height: 1),

          // ── Inline preferences ───────────────────────────────────────────
          if (_showPreferences)
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: AiPreferencesPanel(
                service: svc,
                onClose: () => setState(() => _showPreferences = false),
              ),
            ),

          if (_showPreferences) const Divider(height: 1),

          // ── Main body ────────────────────────────────────────────────────
          Expanded(
            child: AnimatedBuilder(
              animation: svc,
              builder: (context, child) {
                if (svc.isConnected) {
                  return AiChatView(
                    service: svc,
                    contextBuilder: _contextBuilder,
                  );
                }
                return AiSetupView(service: svc);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pane header ───────────────────────────────────────────────────────────────

class _PaneHeader extends StatelessWidget {
  final AiAssistantService service;
  final bool showPreferences;
  final VoidCallback onTogglePreferences;
  final VoidCallback? onClearHistory;

  const _PaneHeader({
    required this.service,
    required this.showPreferences,
    required this.onTogglePreferences,
    this.onClearHistory,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final svc = service;

    return Container(
      height: 36,
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          // Status dot
          _StatusDot(status: svc.connectionStatus),
          const SizedBox(width: 6),

          // Title
          Expanded(
            child: Text(
              svc.isConnected ? svc.model : 'AI Assistant',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Re-test / status indicator when checking
          if (svc.isChecking)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ),

          // Clear history (connected only)
          if (onClearHistory != null)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
              tooltip: 'Clear history',
              onPressed: onClearHistory,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),

          // Settings gear
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              size: 16,
              color: showPreferences ? cs.primary : null,
            ),
            tooltip: 'AI settings',
            onPressed: onTogglePreferences,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

// ── Status dot ────────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final AiConnectionStatus status;

  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status) {
      case AiConnectionStatus.connected:
        color = const Color(0xFF4CAF50);
      case AiConnectionStatus.checking:
        color = const Color(0xFFFFA726);
      case AiConnectionStatus.disconnected:
        color = const Color(0xFFEF5350);
      case AiConnectionStatus.modelMissing:
        color = const Color(
          0xFFFF7043,
        ); // deep orange — reachable but incomplete
      case AiConnectionStatus.unchecked:
        color = Colors.grey;
    }

    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

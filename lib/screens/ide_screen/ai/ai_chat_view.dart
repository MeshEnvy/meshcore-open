import 'package:flutter/material.dart';

import 'ai_assistant_service.dart';
import 'ai_context_builder.dart';

/// The chat interface shown when Ollama is connected.
class AiChatView extends StatefulWidget {
  final AiAssistantService service;
  final AiContextBuilder contextBuilder;

  const AiChatView({
    super.key,
    required this.service,
    required this.contextBuilder,
  });

  @override
  State<AiChatView> createState() => _AiChatViewState();
}

class _AiChatViewState extends State<AiChatView> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  AiAssistantService get svc => widget.service;
  AiContextBuilder get ctx => widget.contextBuilder;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || svc.isGenerating) return;
    _inputCtrl.clear();
    _inputFocus.requestFocus();
    svc.addListener(_scrollToBottom);
    await svc.sendMessage(msg, contextBuilder: ctx);
    svc.removeListener(_scrollToBottom);
    _scrollToBottom();
  }

  Future<void> _quickAction(String Function() promptBuilder) async {
    if (svc.isGenerating) return;
    svc.addListener(_scrollToBottom);
    await svc.sendMessage(promptBuilder(), contextBuilder: null);
    svc.removeListener(_scrollToBottom);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasScript = ctx.fileName != null;

    return Column(
      children: [
        // ── Context chip ───────────────────────────────────────────────────
        if (hasScript)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            color: cs.surfaceContainerHigh,
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 12,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    ctx.fileName!,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.check_circle_outline, size: 11, color: cs.primary),
                const SizedBox(width: 3),
                Text(
                  'in context',
                  style: TextStyle(fontSize: 10, color: cs.primary),
                ),
              ],
            ),
          ),

        // ── Message list ───────────────────────────────────────────────────
        Expanded(
          child: svc.messages.isEmpty
              ? _EmptyState(
                  hasScript: hasScript,
                  onQuickAction: _quickAction,
                  contextBuilder: ctx,
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: svc.messages.length,
                  itemBuilder: (_, i) =>
                      _MessageBubble(message: svc.messages[i]),
                ),
        ),

        // ── Quick actions ──────────────────────────────────────────────────
        if (hasScript && svc.messages.isEmpty)
          const SizedBox.shrink()
        else if (hasScript)
          _QuickActionsBar(
            onFixErrors: () => _quickAction(ctx.buildFixErrorsPrompt),
            onExplain: () => _quickAction(ctx.buildExplainPrompt),
            onAddComments: () => _quickAction(ctx.buildAddCommentsPrompt),
            onRefactor: () => _quickAction(ctx.buildRefactorPrompt),
            enabled: !svc.isGenerating,
          ),

        const Divider(height: 1),

        // ── Input row ──────────────────────────────────────────────────────
        _InputRow(
          controller: _inputCtrl,
          focusNode: _inputFocus,
          isGenerating: svc.isGenerating,
          onSend: _send,
        ),
      ],
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final AiChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor: cs.primaryContainer,
              child: Icon(
                Icons.auto_awesome,
                size: 13,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUser ? cs.primaryContainer : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isUser ? 12 : 2),
                  bottomRight: Radius.circular(isUser ? 2 : 12),
                ),
              ),
              child: SelectableText(
                message.text.isEmpty ? '…' : message.text,
                style: TextStyle(
                  fontSize: 12,
                  color: isUser ? cs.onPrimaryContainer : cs.onSurface,
                  fontFamily: _looksLikeCode(message.text) ? 'monospace' : null,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  bool _looksLikeCode(String text) =>
      text.contains('```') ||
      text.contains('function ') ||
      text.contains('local ') ||
      text.contains('\n  ');
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasScript;
  final Future<void> Function(String Function()) onQuickAction;
  final AiContextBuilder contextBuilder;

  const _EmptyState({
    required this.hasScript,
    required this.onQuickAction,
    required this.contextBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 32, color: cs.primary),
            const SizedBox(height: 12),
            Text(
              hasScript
                  ? 'Ask anything about your Lua script,\nor tap a quick action below.'
                  : 'Open a Lua file to get\nscript-aware AI assistance.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            if (hasScript) ...[
              const SizedBox(height: 20),
              _QuickActionsBar(
                onFixErrors: () =>
                    onQuickAction(contextBuilder.buildFixErrorsPrompt),
                onExplain: () =>
                    onQuickAction(contextBuilder.buildExplainPrompt),
                onAddComments: () =>
                    onQuickAction(contextBuilder.buildAddCommentsPrompt),
                onRefactor: () =>
                    onQuickAction(contextBuilder.buildRefactorPrompt),
                enabled: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Quick actions bar ─────────────────────────────────────────────────────────

class _QuickActionsBar extends StatelessWidget {
  final VoidCallback onFixErrors;
  final VoidCallback onExplain;
  final VoidCallback onAddComments;
  final VoidCallback onRefactor;
  final bool enabled;

  const _QuickActionsBar({
    required this.onFixErrors,
    required this.onExplain,
    required this.onAddComments,
    required this.onRefactor,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _ActionChip(
            label: 'Fix errors',
            icon: Icons.build_outlined,
            onTap: enabled ? onFixErrors : null,
          ),
          _ActionChip(
            label: 'Explain',
            icon: Icons.lightbulb_outline,
            onTap: enabled ? onExplain : null,
          ),
          _ActionChip(
            label: 'Comment',
            icon: Icons.comment_outlined,
            onTap: enabled ? onAddComments : null,
          ),
          _ActionChip(
            label: 'Refactor',
            icon: Icons.auto_fix_high,
            onTap: enabled ? onRefactor : null,
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 13),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: onTap == null ? cs.surfaceContainerHighest : null,
    );
  }
}

// ── Input row ─────────────────────────────────────────────────────────────────

class _InputRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isGenerating;
  final Future<void> Function(String) onSend;

  const _InputRow({
    required this.controller,
    required this.focusNode,
    required this.isGenerating,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Ask about your Lua script…',
                hintStyle: TextStyle(fontSize: 12),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: onSend,
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: isGenerating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            onPressed: isGenerating ? null : () => onSend(controller.text),
            tooltip: 'Send',
          ),
        ],
      ),
    );
  }
}

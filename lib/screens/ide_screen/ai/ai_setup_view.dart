import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_assistant_service.dart';

/// Shown when Ollama is not connected (or model is missing).
/// Walks the user through install → pull → configure → test.
class AiSetupView extends StatefulWidget {
  final AiAssistantService service;

  const AiSetupView({super.key, required this.service});

  @override
  State<AiSetupView> createState() => _AiSetupViewState();
}

class _AiSetupViewState extends State<AiSetupView> {
  late final TextEditingController _endpointCtrl;
  late final TextEditingController _modelCtrl;

  @override
  void initState() {
    super.initState();
    _endpointCtrl = TextEditingController(text: widget.service.endpoint);
    _modelCtrl = TextEditingController(text: widget.service.model);
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _saveAndTest() {
    widget.service.endpoint = _endpointCtrl.text.trim();
    widget.service.model = _modelCtrl.text.trim();
    widget.service.savePreferences();
    widget.service.testConnection();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final svc = widget.service;
    final isChecking = svc.isChecking;
    final isDisconnected =
        svc.connectionStatus == AiConnectionStatus.disconnected;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Header ────────────────────────────────────────────────────────
        Row(
          children: [
            Icon(Icons.auto_awesome, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'AI Assistant',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Text(
          'Connect a local Ollama instance for Lua code assistance. '
          'Completely private — nothing leaves your machine.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),

        // ── Step 1 ────────────────────────────────────────────────────────
        _StepCard(
          step: '1',
          title: 'Install Ollama',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Visit ollama.com or run:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              _CopyableCommand('brew install ollama'),
              const SizedBox(height: 4),
              _CopyableCommand('ollama serve'),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Step 2 ────────────────────────────────────────────────────────
        _StepCard(
          step: '2',
          title: 'Pull a model',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recommended (fast, Lua-aware):',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              _CopyableCommand('ollama pull qwen2.5-coder:7b'),
              const SizedBox(height: 4),
              Text(
                'Or use codellama:7b, deepseek-coder:6.7b, etc.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Step 3 ────────────────────────────────────────────────────────
        _StepCard(
          step: '3',
          title: 'Configure',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LabeledField(
                label: 'Ollama endpoint',
                controller: _endpointCtrl,
                hint: 'http://localhost:11434',
              ),
              const SizedBox(height: 8),
              _LabeledField(
                label: 'Model',
                controller: _modelCtrl,
                hint: 'qwen2.5-coder:7b',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── CORS note (web only) ──────────────────────────────────────────
        _CorsHint(),
        const SizedBox(height: 16),

        // ── Model-missing banner ──────────────────────────────────────────
        // Shown when Ollama responds but the selected model isn't pulled yet.
        if (svc.isModelMissing) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF7043)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.upload_outlined,
                      color: Color(0xFFFF7043),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ollama is running, but model '
                        '"${svc.model}" hasn\'t been pulled yet.',
                        style: const TextStyle(
                          color: Color(0xFFBF360C),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CopyableCommand('ollama pull ${svc.model}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Unreachable banner ────────────────────────────────────────────
        // Shown when Ollama itself can't be contacted.
        if (isDisconnected) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: cs.onErrorContainer,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Could not reach Ollama. Make sure it\'s running '
                    '("ollama serve") and the endpoint is correct.',
                    style: TextStyle(color: cs.onErrorContainer, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Test button ───────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: isChecking ? null : _saveAndTest,
            icon: isChecking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.electrical_services, size: 16),
            label: Text(isChecking ? 'Testing…' : 'Test Connection'),
          ),
        ),
      ],
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final String step;
  final String title;
  final Widget child;

  const _StepCard({
    required this.step,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    step,
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _CopyableCommand extends StatelessWidget {
  final String command;

  const _CopyableCommand(this.command);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: command));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied to clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                command,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.copy, size: 13, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

/// Shown only on web builds — reminds the user about the CORS requirement.
class _CorsHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Only show on web
    if (!const bool.fromEnvironment('dart.library.html')) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: cs.onTertiaryContainer),
              const SizedBox(width: 6),
              Text(
                'Web / CORS note',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onTertiaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Start Ollama with CORS enabled:',
            style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer),
          ),
          const SizedBox(height: 4),
          _CopyableCommand('OLLAMA_ORIGINS="*" ollama serve'),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'ai_assistant_service.dart';

/// Inline preferences panel — slides down within the AI pane.
/// Wraps fields for endpoint, model, and a re-test button.
class AiPreferencesPanel extends StatefulWidget {
  final AiAssistantService service;
  final VoidCallback onClose;

  const AiPreferencesPanel({
    super.key,
    required this.service,
    required this.onClose,
  });

  @override
  State<AiPreferencesPanel> createState() => _AiPreferencesPanelState();
}

class _AiPreferencesPanelState extends State<AiPreferencesPanel> {
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

  void _save() {
    widget.service.endpoint = _endpointCtrl.text.trim();
    widget.service.model = _modelCtrl.text.trim();
    widget.service.savePreferences();
    widget.service.testConnection();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final availableModels = widget.service.availableModels;

    return Container(
      color: cs.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header row ───────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.settings_outlined, size: 14),
              const SizedBox(width: 6),
              const Text(
                'AI Settings',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Endpoint ─────────────────────────────────────────────────────
          const Text(
            'Ollama endpoint',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _endpointCtrl,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: 'http://localhost:11434',
              hintStyle: TextStyle(fontSize: 12),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),

          // ── Model ─────────────────────────────────────────────────────────
          const Text(
            'Model',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          if (availableModels.isEmpty)
            TextField(
              controller: _modelCtrl,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: 'qwen2.5-coder:7b',
                hintStyle: TextStyle(fontSize: 12),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: availableModels.contains(widget.service.model)
                  ? widget.service.model
                  : availableModels.first,
              items: availableModels
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(
                        m,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  _modelCtrl.text = v;
                  widget.service.model = v;
                }
              },
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 14),

          // ── Actions ───────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onClose,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Save & test'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

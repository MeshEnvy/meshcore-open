import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Custom Markdown builder that renders fenced code blocks with a header bar
/// containing Copy and Apply buttons.
///
/// "Apply" replaces the active editor content. Pass [onApply] to wire this up.
class AiCodeBlockBuilder extends MarkdownElementBuilder {
  final void Function(String code)? onApply;

  AiCodeBlockBuilder({this.onApply});

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // Only handle <pre> (fenced blocks). Inline <code> is left to the default renderer.
    if (element.tag != 'pre') return null;

    // Extract raw text from the nested <code> child.
    final code = _extractCode(element);
    if (code.isEmpty) return null;

    // Detect language hint from the class attribute, e.g. "language-lua".
    final lang = _detectLanguage(element);

    return _CodeBlock(code: code, language: lang, onApply: onApply);
  }

  String _extractCode(md.Element element) {
    final buf = StringBuffer();
    for (final child in element.children ?? <md.Node>[]) {
      buf.write(_nodeText(child));
    }
    // Trim one trailing newline that the Markdown parser always adds.
    final raw = buf.toString();
    return raw.endsWith('\n') ? raw.substring(0, raw.length - 1) : raw;
  }

  String _nodeText(md.Node node) {
    if (node is md.Text) return node.text;
    if (node is md.Element) {
      return (node.children ?? []).map(_nodeText).join();
    }
    return '';
  }

  String? _detectLanguage(md.Element pre) {
    final codeEl = (pre.children ?? []).whereType<md.Element>().firstOrNull;
    final cls = codeEl?.attributes['class'] ?? '';
    if (cls.startsWith('language-')) {
      return cls.substring('language-'.length);
    }
    return null;
  }
}

// ── Code block widget ─────────────────────────────────────────────────────────

class _CodeBlock extends StatefulWidget {
  final String code;
  final String? language;
  final void Function(String)? onApply;

  const _CodeBlock({required this.code, this.language, this.onApply});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _applied = false;
  bool _copied = false;

  void _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  void _apply() {
    widget.onApply?.call(widget.code);
    setState(() => _applied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _applied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    const codeBackground = Color(0xFF1E1E1E);
    const codeText = Color(0xFFD4D4D4);
    final cs = Theme.of(context).colorScheme;
    final canApply = widget.onApply != null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: codeBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF444444)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header bar ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF2A2A2A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(5),
                topRight: Radius.circular(5),
              ),
            ),
            child: Row(
              children: [
                // Language tag
                if (widget.language != null) ...[
                  Text(
                    widget.language!,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: cs.primary.withValues(alpha: 0.8),
                    ),
                  ),
                  const Spacer(),
                ] else
                  const Spacer(),

                // Copy button
                _HeaderButton(
                  icon: _copied ? Icons.check : Icons.copy_outlined,
                  label: _copied ? 'Copied' : 'Copy',
                  onTap: _copy,
                  highlight: _copied,
                ),

                // Apply button (only when editor is open)
                if (canApply) ...[
                  const SizedBox(width: 8),
                  _HeaderButton(
                    icon: _applied
                        ? Icons.check_circle_outline
                        : Icons.file_open_outlined,
                    label: _applied ? 'Applied!' : 'Apply',
                    onTap: _apply,
                    highlight: _applied,
                    primary: true,
                  ),
                ],
              ],
            ),
          ),

          // ── Code body ─────────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              widget.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: codeText,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;
  final bool primary;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = highlight
        ? const Color(0xFF4CAF50)
        : primary
        ? cs.primary
        : const Color(0xFF888888);

    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }
}

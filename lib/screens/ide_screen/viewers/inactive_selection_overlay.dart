import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

/// Tracks selection in a [CodeController] and, when the editor loses focus,
/// paints a "ghost" inactive-selection highlight via a [OverlayEntry].
///
/// Mount this widget as the direct parent of the [CodeField].  Pass in the
/// [editorFocusNode] that belongs to that [CodeField] and the [controller].
///
/// When focus is inside the editor the default selection rendering kicks in.
/// When focus moves elsewhere (e.g. the AI chat input) this widget renders a
/// faint highlight band over the same line range so the user knows which code
/// they had selected.
class InactiveSelectionOverlay extends StatefulWidget {
  final CodeController controller;
  final FocusNode editorFocusNode;
  final Widget child;

  const InactiveSelectionOverlay({
    super.key,
    required this.controller,
    required this.editorFocusNode,
    required this.child,
  });

  @override
  State<InactiveSelectionOverlay> createState() =>
      _InactiveSelectionOverlayState();
}

class _InactiveSelectionOverlayState extends State<InactiveSelectionOverlay> {
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  // The selection snapshot taken at the moment focus left the editor.
  TextSelection? _frozenSelection;
  // The full text at the moment focus left (needed to count line breaks).
  String _frozenText = '';

  @override
  void initState() {
    super.initState();
    widget.editorFocusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    widget.editorFocusNode.removeListener(_onFocusChange);
    widget.controller.removeListener(_onControllerChange);
    _removeOverlay();
    super.dispose();
  }

  // ── listeners ───────────────────────────────────────────────────────────────

  void _onFocusChange() {
    if (widget.editorFocusNode.hasFocus) {
      // Editor regained focus — the real selection overlay takes over.
      _removeOverlay();
      _frozenSelection = null;
    } else {
      // Editor just lost focus — freeze the current selection.
      final sel = widget.controller.selection;
      if (!sel.isValid || sel.isCollapsed) {
        // No real selection — nothing to show.
        _removeOverlay();
        _frozenSelection = null;
        return;
      }
      _frozenSelection = sel;
      _frozenText = widget.controller.text;
      _showOverlay();
    }
  }

  void _onControllerChange() {
    // If the text changes while we are showing the ghost (e.g. the user types
    // in the AI box and then... actually the editor text shouldn't change), or
    // the user scrolls — just refresh the overlay position.
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  // ── overlay management ───────────────────────────────────────────────────────

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // ── overlay builder ──────────────────────────────────────────────────────────

  Widget _buildOverlay(BuildContext overlayCtx) {
    final sel = _frozenSelection;
    if (sel == null || !sel.isValid || sel.isCollapsed) {
      return const SizedBox.shrink();
    }

    // Find the screen-space bounding box of our CodeField container.
    final RenderBox? box =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return const SizedBox.shrink();

    final Offset origin = box.localToGlobal(Offset.zero);
    final Size size = box.size;

    // ── Line geometry ─────────────────────────────────────────────────────────
    // CodeField uses `textStyle: TextStyle(fontFamily: 'monospace', fontSize: 14)`.
    // The line height for code fields in flutter_code_editor is typically
    // fontSize * 1.5 (the default Flutter line-height multiplier).
    const double fontSize = 14.0;
    const double lineHeight = fontSize * 1.5; // ~21px
    // The gutter width is estimated; the default in flutter_code_editor is ~48px
    // for 3-digit line numbers.  We cannot read it precisely, so we use a
    // conservative estimate that errs on the side of a slightly narrow band.
    const double gutterWidth = 48.0;

    // Count the start and end line indices (0-based).
    final text = _frozenText;
    final startLine = _lineOfOffset(text, sel.start);
    final endLine = _lineOfOffset(text, sel.end);

    // Build one highlight rect per selected line.
    final List<Widget> bands = [];
    for (int line = startLine; line <= endLine; line++) {
      final top = origin.dy + line * lineHeight;
      // Clamp to the visible area of the code field.
      if (top + lineHeight < origin.dy || top > origin.dy + size.height) {
        continue;
      }
      bands.add(
        Positioned(
          left: origin.dx + gutterWidth,
          top: top.clamp(origin.dy, origin.dy + size.height - lineHeight),
          width: size.width - gutterWidth,
          height: lineHeight,
          child: Container(
            color: const Color(0x4D264F78), // VS Code-style inactive selection
          ),
        ),
      );
    }

    return Stack(children: bands);
  }

  /// Returns the 0-based line index for a character offset in [text].
  static int _lineOfOffset(String text, int offset) {
    if (offset <= 0) return 0;
    final clamped = offset.clamp(0, text.length);
    return '\n'.allMatches(text.substring(0, clamped)).length;
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _fieldKey, child: widget.child);
  }
}

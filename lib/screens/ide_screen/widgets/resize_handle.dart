import 'package:flutter/material.dart';

/// A thin horizontal bar (dragged vertically) that resizes a pane height.
///
/// Used between the code editor and the inline log pane.
class VerticalResizeHandle extends StatelessWidget {
  final void Function(double dy) onDrag;

  const VerticalResizeHandle({super.key, required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: Container(
          height: 6,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(
            child: Icon(
              Icons.drag_handle,
              size: 14,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin vertical bar (dragged horizontally) that resizes a pane width.
///
/// Used between the left sidebar and the right editor pane.
class HorizontalResizeHandle extends StatelessWidget {
  final void Function(double dx) onDrag;

  const HorizontalResizeHandle({super.key, required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 6,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(
            child: Container(
              width: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}

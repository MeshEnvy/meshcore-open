import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../../services/mal/vfs/vfs.dart';
import '../ide_controller.dart';

/// Displays the virtual-filesystem tree with drag-drop support.
class IdeFilePanel extends StatelessWidget {
  final IdeController ctrl;
  const IdeFilePanel({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: (details) {
        String basePath = ctrl.drivePath;
        if (ctrl.selectedNode != null) {
          basePath = ctrl.selectedNode!.isDir
              ? ctrl.selectedNode!.path
              : (ctrl.selectedNode!.path.split('/')..removeLast()).join('/');
        }
        ctrl.performDrop(details, basePath);
      },
      onDragEntered: (_) {
        ctrl.dragging = true;
        ctrl.notify();
      },
      onDragExited: (_) {
        ctrl.dragging = false;
        ctrl.notify();
      },
      child: Container(
        decoration: BoxDecoration(
          color: ctrl.dragging
              ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.2)
              : null,
          border: Border(
            right: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
          ),
        ),
        child: Column(
          children: [
            // ── Toolbar ────────────────────────────────────────────────
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Files',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: 'New',
                    padding: EdgeInsets.zero,
                    onSelected: (action) async {
                      if (action == 'file') {
                        await ctrl.createEntity(isFile: true, ctx: context);
                      } else if (action == 'dir') {
                        await ctrl.createEntity(isFile: false, ctx: context);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'file',
                        child: Row(
                          children: [
                            Icon(Icons.insert_drive_file, size: 18),
                            SizedBox(width: 8),
                            Text('New File'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'dir',
                        child: Row(
                          children: [
                            Icon(Icons.folder, size: 18),
                            SizedBox(width: 8),
                            Text('New Directory'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ── File tree ─────────────────────────────────────────────
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onSecondaryTapDown: (details) =>
                    _showContextMenu(context, details.globalPosition, null),
                child: ctrl.files.isEmpty
                    ? const Center(child: Text('No files found'))
                    : ListView.builder(
                        itemCount: ctrl.files.length,
                        itemBuilder: (ctx, index) {
                          final entity = ctrl.files[index];
                          final isFile = !entity.isDir;
                          final relativePath = entity.path.replaceFirst(
                            '${ctrl.drivePath}/',
                            '',
                          );
                          final depth = relativePath.split('/').length - 1;
                          final isSelected =
                              ctrl.selectedNode?.path == entity.path;

                          return DropTarget(
                            onDragDone: (details) {
                              String basePath = entity.path;
                              if (!entity.isDir) {
                                basePath = (entity.path.split(
                                  '/',
                                )..removeLast()).join('/');
                              }
                              ctrl.performDrop(details, basePath);
                            },
                            onDragEntered: (_) {
                              ctrl.hoveredNodePath = entity.path;
                              ctrl.notify();
                            },
                            onDragExited: (_) {
                              ctrl.hoveredNodePath = null;
                              ctrl.notify();
                            },
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onSecondaryTapDown: (details) => _showContextMenu(
                                ctx,
                                details.globalPosition,
                                entity,
                              ),
                              child: ListTile(
                                leading: Padding(
                                  padding: EdgeInsets.only(left: depth * 12.0),
                                  child: Icon(
                                    isFile
                                        ? Icons.insert_drive_file
                                        : Icons.folder,
                                    size: 20,
                                    color: isFile
                                        ? null
                                        : Theme.of(ctx).colorScheme.primary,
                                  ),
                                ),
                                title: Text(
                                  relativePath.split('/').last,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight:
                                        (isSelected && ctrl.hasUnsavedChanges)
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                selected:
                                    isSelected ||
                                    ctrl.hoveredNodePath == entity.path,
                                selectedTileColor: Theme.of(
                                  ctx,
                                ).colorScheme.primaryContainer,
                                onTap: () => ctrl.selectNode(entity, ctx),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    VfsNode? entity,
  ) {
    if (entity != null && ctrl.selectedNode != entity) {
      ctrl.selectNode(entity, context);
    }

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(
          value: 'file',
          child: Row(
            children: [
              Icon(Icons.insert_drive_file, size: 20),
              SizedBox(width: 8),
              Text('New File'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'dir',
          child: Row(
            children: [
              Icon(Icons.folder, size: 20),
              SizedBox(width: 8),
              Text('New Directory'),
            ],
          ),
        ),
        if (entity != null) ...[
          const PopupMenuDivider(),
          if (!entity.isDir && entity.path.toLowerCase().endsWith('.lua'))
            PopupMenuItem(
              value: 'run',
              child: Row(
                children: [
                  Icon(
                    Icons.play_arrow,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text('Run Script'),
                ],
              ),
            ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 20, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ],
    ).then((value) async {
      if (!context.mounted) return;
      if (value == 'file') {
        await ctrl.createEntity(isFile: true, ctx: context);
      } else if (value == 'dir') {
        await ctrl.createEntity(isFile: false, ctx: context);
      } else if (value == 'run' && entity != null) {
        await ctrl.runScript(entity, context);
      } else if (value == 'delete' && entity != null) {
        await ctrl.deleteEntity(entity, context);
      }
    });
  }
}

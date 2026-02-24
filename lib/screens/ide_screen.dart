import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/lua.dart' as highlight_lua;

import '../services/vfs/vfs.dart';

import '../l10n/l10n.dart';

class IdeScreen extends StatefulWidget {
  const IdeScreen({super.key});

  @override
  State<IdeScreen> createState() => _IdeScreenState();
}

class _IdeScreenState extends State<IdeScreen> {
  String _drivePath = '';
  List<VfsNode> _files = [];
  VfsNode? _selectedNode;
  VfsNode? _selectedFile;
  CodeController? _codeController;
  String? _originalContent;
  bool _hasUnsavedChanges = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      BrowserContextMenu.disableContextMenu();
    }
    _initDriveDirs();
  }

  @override
  void dispose() {
    if (kIsWeb) {
      BrowserContextMenu.enableContextMenu();
    }
    _codeController?.dispose();
    super.dispose();
  }

  Future<void> _initDriveDirs() async {
    try {
      // TODO: Get actual nodeId
      final nodeId = 'default_node';
      final vfs = VirtualFileSystem.get();
      _drivePath = await vfs.init(nodeId);

      // Let's create an autoexec.lua dummy file if it doesn't exist
      final autoexecPath = '$_drivePath/autoexec.lua';
      if (!await vfs.exists(autoexecPath)) {
        await vfs.writeAsString(autoexecPath, 'print("hello world")\n');
      }

      await _loadFiles();
    } catch (e) {
      debugPrint('Error initializing IDE drive directory: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFiles() async {
    try {
      final vfs = VirtualFileSystem.get();
      if (await vfs.exists(_drivePath)) {
        // Simple recursive load helper
        final files = <VfsNode>[];
        Future<void> loadDir(String path) async {
          final children = await vfs.list(path);
          for (final child in children) {
            files.add(child);
            if (child.isDir) {
              await loadDir(child.path);
            }
          }
        }

        await loadDir(_drivePath);

        files.sort((a, b) {
          final aRelative = a.path.replaceFirst('$_drivePath/', '');
          final bRelative = b.path.replaceFirst('$_drivePath/', '');
          final aSegments = aRelative.split('/');
          final bSegments = bRelative.split('/');

          final minLen = aSegments.length < bSegments.length
              ? aSegments.length
              : bSegments.length;

          for (var i = 0; i < minLen; i++) {
            if (aSegments[i] != bSegments[i]) {
              final isADirAtSegment = (i < aSegments.length - 1) || a.isDir;
              final isBDirAtSegment = (i < bSegments.length - 1) || b.isDir;

              if (isADirAtSegment && !isBDirAtSegment) return -1;
              if (!isADirAtSegment && isBDirAtSegment) return 1;

              return aSegments[i].toLowerCase().compareTo(
                bSegments[i].toLowerCase(),
              );
            }
          }

          return aSegments.length.compareTo(bSegments.length);
        });
        if (mounted) {
          setState(() {
            _files = files;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading files: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _promptDiscardChanges() async {
    if (!_hasUnsavedChanges) return true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.ide_discardTitle),
          content: Text(context.l10n.ide_discardConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(context.l10n.ide_discardAction),
            ),
            TextButton(
              onPressed: () async {
                await _saveCurrentFile();
                if (context.mounted) {
                  Navigator.pop(context, true);
                }
              },
              child: Text(context.l10n.ide_saveAction),
            ),
          ],
        );
      },
    );
    return confirm == true;
  }

  Future<void> _selectNode(VfsNode entity) async {
    if (_hasUnsavedChanges &&
        !entity.isDir &&
        entity.path != _selectedFile?.path) {
      final canSwitch = await _promptDiscardChanges();
      if (!canSwitch) return;
    }

    setState(() {
      _selectedNode = entity;
    });
    if (!entity.isDir) {
      try {
        setState(() {
          _selectedFile = entity;
          _hasUnsavedChanges = false;
        });
        final vfs = VirtualFileSystem.get();
        final content = await vfs.readAsString(entity.path);
        if (mounted) {
          _originalContent = content;
          final controller = CodeController(
            text: content,
            language: highlight_lua.lua,
          );
          controller.addListener(() {
            if (!mounted) return;
            final isChanged = controller.text != _originalContent;
            if (_hasUnsavedChanges != isChanged) {
              setState(() {
                _hasUnsavedChanges = isChanged;
              });
            }
          });
          setState(() {
            _codeController = controller;
          });
        }
      } catch (e) {
        debugPrint('Error selecting file: $e');
      }
    }
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    VfsNode? entity,
  ) {
    if (entity != null && _selectedNode != entity) {
      _selectNode(entity);
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
        PopupMenuItem(
          value: 'file',
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file, size: 20),
              const SizedBox(width: 8),
              Text(context.l10n.ide_newFile),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'dir',
          child: Row(
            children: [
              const Icon(Icons.folder, size: 20),
              const SizedBox(width: 8),
              Text(context.l10n.ide_newDirectory),
            ],
          ),
        ),
        if (entity != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  context.l10n.common_delete,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value == 'file') {
        _showCreateDialog(isFile: true);
      } else if (value == 'dir') {
        _showCreateDialog(isFile: false);
      } else if (value == 'delete' && entity != null) {
        _deleteEntity(entity);
      }
    });
  }

  Future<void> _saveCurrentFile() async {
    if (_selectedFile != null && _codeController != null) {
      try {
        final vfs = VirtualFileSystem.get();
        await vfs.writeAsString(_selectedFile!.path, _codeController!.text);
        if (mounted) {
          _originalContent = _codeController!.text;
          setState(() {
            _hasUnsavedChanges = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.l10n.common_save} successful')),
          );
        }
      } catch (e) {
        debugPrint('Error saving file: $e');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to save file: $e')));
        }
      }
    }
  }

  Future<void> _showCreateDialog({required bool isFile}) async {
    final TextEditingController controller = TextEditingController();
    final String title = isFile
        ? context.l10n.ide_newFile
        : context.l10n.ide_newDirectory;
    final String hint = isFile
        ? context.l10n.ide_fileName
        : context.l10n.ide_dirName;

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: hint),
            autofocus: true,
            onSubmitted: (value) {
              Navigator.pop(context, value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(context.l10n.common_create),
            ),
          ],
        );
      },
    ).then((value) async {
      if (value != null && value is String && value.trim().isNotEmpty) {
        String basePath = _drivePath;
        if (_selectedNode != null) {
          if (_selectedNode!.isDir) {
            basePath = _selectedNode!.path;
          } else {
            // Need to get parent dir path
            final parts = _selectedNode!.path.split('/');
            parts.removeLast();
            basePath = parts.join('/');
          }
        }
        final path = '$basePath/${value.trim()}';
        try {
          final vfs = VirtualFileSystem.get();
          if (isFile) {
            await vfs.createFile(path);
          } else {
            await vfs.createDir(path);
          }
          await _loadFiles();
        } catch (e) {
          debugPrint('Error creating entity: $e');
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Error: $e')));
          }
        }
      }
    });
  }

  Future<void> _deleteEntity(VfsNode entity) async {
    final isFile = !entity.isDir;
    final relativePath = entity.path.replaceFirst('$_drivePath/', '');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.ide_deleteConfirmTitle),
          content: Text(
            isFile
                ? context.l10n.ide_deleteFileConfirm(relativePath)
                : context.l10n.ide_deleteDirConfirm(relativePath),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(context.l10n.common_delete),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        final vfs = VirtualFileSystem.get();
        await vfs.delete(entity.path);
        if (_selectedFile?.path == entity.path ||
            (!isFile &&
                _selectedFile?.path.startsWith('${entity.path}/') == true)) {
          setState(() {
            _selectedFile = null;
            _codeController = null;
            _hasUnsavedChanges = false;
          });
        }
        if (_selectedNode?.path == entity.path ||
            (!isFile &&
                _selectedNode?.path.startsWith('${entity.path}/') == true)) {
          setState(() {
            _selectedNode = null;
          });
        }
        await _loadFiles();
      } catch (e) {
        debugPrint('Error deleting entity: $e');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            _saveCurrentFile(),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            _saveCurrentFile(),
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: !_hasUnsavedChanges,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final shouldPop = await _promptDiscardChanges();
            if (shouldPop && context.mounted) {
              setState(() {
                _hasUnsavedChanges = false;
              });
              if (Navigator.canPop(context)) {
                Navigator.pop(context, result);
              }
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                '${context.l10n.appSettings_ide}${_hasUnsavedChanges ? '*' : ''}',
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _selectedNode != null
                      ? () => _deleteEntity(_selectedNode!)
                      : null,
                  tooltip: context.l10n.common_delete,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.add),
                  tooltip: 'New',
                  onSelected: (action) {
                    if (action == 'file') {
                      _showCreateDialog(isFile: true);
                    } else if (action == 'dir') {
                      _showCreateDialog(isFile: false);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'file',
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file, size: 20),
                          const SizedBox(width: 8),
                          Text(context.l10n.ide_newFile),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'dir',
                      child: Row(
                        children: [
                          const Icon(Icons.folder, size: 20),
                          const SizedBox(width: 8),
                          Text(context.l10n.ide_newDirectory),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_selectedFile != null)
                  IconButton(
                    icon: const Icon(Icons.save),
                    onPressed: _saveCurrentFile,
                    tooltip: context.l10n.common_save,
                  ),
              ],
            ),
            body: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      // Left pane: file tree
                      Expanded(
                        flex: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: Colors.grey.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onSecondaryTapDown: (details) => _showContextMenu(
                              context,
                              details.globalPosition,
                              null,
                            ),
                            child: _files.isEmpty
                                ? const Center(child: Text('No files found'))
                                : ListView.builder(
                                    itemCount: _files.length,
                                    itemBuilder: (context, index) {
                                      final entity = _files[index];
                                      final isFile = !entity.isDir;
                                      final relativePath = entity.path
                                          .replaceFirst('$_drivePath/', '');
                                      final isSelected =
                                          _selectedNode?.path == entity.path;

                                      // Add padding to simulate folder depth
                                      final depth =
                                          relativePath.split('/').length - 1;

                                      return GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onSecondaryTapDown: (details) {
                                          _showContextMenu(
                                            context,
                                            details.globalPosition,
                                            entity,
                                          );
                                        },
                                        child: ListTile(
                                          leading: Padding(
                                            padding: EdgeInsets.only(
                                              left: depth * 12.0,
                                            ),
                                            child: Icon(
                                              isFile
                                                  ? Icons.insert_drive_file
                                                  : Icons.folder,
                                              size: 20,
                                              color: isFile
                                                  ? null
                                                  : Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                            ),
                                          ),
                                          title: Text(
                                            relativePath.split('/').last,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight:
                                                  (isSelected &&
                                                      _hasUnsavedChanges)
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          selected: isSelected,
                                          selectedTileColor: Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer,
                                          onTap: () {
                                            _selectNode(entity);
                                          },
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                      // Right pane: code editor
                      Expanded(
                        flex: 2,
                        child: _selectedFile == null || _codeController == null
                            ? const Center(child: Text('Select a file to edit'))
                            : Column(
                                children: [
                                  if (_hasUnsavedChanges)
                                    Container(
                                      width: double.infinity,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.errorContainer,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                        horizontal: 8,
                                      ),
                                      child: Text(
                                        context.l10n.ide_unsavedChanges,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onErrorContainer,
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  Expanded(
                                    child: CodeTheme(
                                      data: CodeThemeData(
                                        styles: monokaiSublimeTheme,
                                      ),
                                      child: CodeField(
                                        controller: _codeController!,
                                        expands: true,
                                        textStyle: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 14,
                                        ),
                                      ),
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
}

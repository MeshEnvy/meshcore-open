import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/lua.dart' as highlight_lua;

import '../l10n/l10n.dart';

class IdeScreen extends StatefulWidget {
  const IdeScreen({super.key});

  @override
  State<IdeScreen> createState() => _IdeScreenState();
}

class _IdeScreenState extends State<IdeScreen> {
  String _drivePath = '';
  List<FileSystemEntity> _files = [];
  FileSystemEntity? _selectedNode;
  File? _selectedFile;
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
      final docsDir = await getApplicationDocumentsDirectory();
      final driveDir = Directory('${docsDir.path}/drive');
      if (!await driveDir.exists()) {
        await driveDir.create(recursive: true);

        // Let's create an autoexec.lua dummy file if it doesn't exist
        final autoexecFile = File('${driveDir.path}/autoexec.lua');
        if (!await autoexecFile.exists()) {
          await autoexecFile.writeAsString('print("hello world")\n');
        }
      }
      _drivePath = driveDir.path;
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
      final dir = Directory(_drivePath);
      if (await dir.exists()) {
        final files = dir.listSync(recursive: true);
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
              final isADirAtSegment =
                  (i < aSegments.length - 1) || (a is Directory);
              final isBDirAtSegment =
                  (i < bSegments.length - 1) || (b is Directory);

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

  Future<void> _selectNode(FileSystemEntity entity) async {
    if (_hasUnsavedChanges &&
        entity is File &&
        entity.path != _selectedFile?.path) {
      final canSwitch = await _promptDiscardChanges();
      if (!canSwitch) return;
    }

    setState(() {
      _selectedNode = entity;
    });
    if (entity is File) {
      try {
        setState(() {
          _selectedFile = entity;
          _hasUnsavedChanges = false;
        });
        final content = await entity.readAsString();
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
    FileSystemEntity? entity,
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
        await _selectedFile!.writeAsString(_codeController!.text);
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
          if (_selectedNode is Directory) {
            basePath = _selectedNode!.path;
          } else {
            basePath = _selectedNode!.parent.path;
          }
        }
        final path = '$basePath/${value.trim()}';
        try {
          if (isFile) {
            final newFile = File(path);
            await newFile.create(recursive: true);
          } else {
            final newDir = Directory(path);
            await newDir.create(recursive: true);
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

  Future<void> _deleteEntity(FileSystemEntity entity) async {
    final isFile = entity is File;
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
        await entity.delete(recursive: true);
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
    return PopScope(
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
                                  final isFile = entity is File;
                                  final relativePath = entity.path.replaceFirst(
                                    '$_drivePath/',
                                    '',
                                  );
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
                                              (isSelected && _hasUnsavedChanges)
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
    );
  }
}

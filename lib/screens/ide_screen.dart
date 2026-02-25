import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/lua.dart' as highlight_lua;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'package:provider/provider.dart';
import '../services/mal/vfs/vfs.dart';
import '../services/mal/mal_api.dart';
import '../utils/app_logger.dart';

import '../l10n/l10n.dart';

enum FileDisplayMode { code, image, pdf, unsupported }

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
  FileDisplayMode _displayMode = FileDisplayMode.code;
  Uint8List? _fileBytes;
  bool _isLoadingFile = false;
  bool _hasUnsavedChanges = false;
  bool _isLoading = true;
  bool _dragging = false;
  String? _hoveredNodePath;

  List<MapEntry<String, String>> _envVars = [];
  bool _isLoadingEnv = true;
  String? _selectedEnvKey;

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
    if (kDebugMode) print('[IdeScreen] _initDriveDirs starting...');
    try {
      final malApi = context.read<MalApi>();
      _drivePath = malApi.homePath;

      // Let's create an autoexec.lua dummy file if it doesn't exist
      final autoexecPath = '$_drivePath/autoexec.lua';
      if (!await malApi.fexists(autoexecPath)) {
        await malApi.fwrite(autoexecPath, 'print("hello world")\n');
      }

      if (kDebugMode)
        print('[IdeScreen] autoexec.lua checked. Loading files...');
      await _loadFiles();
      await _loadEnvVars();
    } catch (e) {
      appLogger.error(
        'Error initializing IDE drive directory: $e',
        tag: 'IdeScreen',
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFiles() async {
    if (kDebugMode) print('[IdeScreen] _loadFiles starting...');
    try {
      final malApi = context.read<MalApi>();
      if (await malApi.fexists(_drivePath)) {
        // Simple recursive load helper
        final files = <VfsNode>[];
        Future<void> loadDir(String path) async {
          final children = await malApi.flist(path);
          for (final child in children) {
            files.add(child);
            if (child.isDir) {
              await loadDir(child.path);
            }
          }
        }

        if (kDebugMode)
          print('[IdeScreen] loadDir basic path: $_drivePath starting...');
        await loadDir(_drivePath);
        if (kDebugMode)
          print(
            '[IdeScreen] loadDir finished. Found ${files.length} flat entities',
          );

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
        if (kDebugMode)
          print(
            '[IdeScreen] _loadFiles: setState called with ${files.length} files',
          );
        if (mounted) {
          setState(() {
            _files = files;
            _isLoading = false;
          });
        }
      } else {
        if (kDebugMode)
          print(
            '[IdeScreen] _loadFiles: _drivePath $_drivePath does not exist',
          );
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) print('[IdeScreen] Error loading files: $e');
      appLogger.error('Error loading files: $e', tag: 'IdeScreen');
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

  Future<void> _loadEnvVars() async {
    setState(() => _isLoadingEnv = true);
    try {
      final malApi = context.read<MalApi>();
      final keys = await malApi.getKeys(scope: 'env');
      final List<MapEntry<String, String>> vars = [];

      for (final key in keys) {
        if (!key.startsWith('vfs:')) {
          final value = await malApi.getEnv(key) ?? '';
          vars.add(MapEntry(key, value));
        }
      }

      vars.sort((a, b) => a.key.compareTo(b.key));
      if (mounted) {
        setState(() {
          _envVars = vars;
          _isLoadingEnv = false;
        });
      }
    } catch (e) {
      appLogger.error('Error loading env vars: $e', tag: 'IdeScreen');
      if (mounted) {
        setState(() => _isLoadingEnv = false);
      }
    }
  }

  Future<void> _deleteEnvVar(String key) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.appSettings_deleteSecretTitle),
        content: Text(context.l10n.appSettings_deleteSecretConfirm(key)),
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
      ),
    );
    if (confirm == true) {
      try {
        final malApi = context.read<MalApi>();
        await malApi.deleteKey(key, scope: 'env');
        if (_selectedEnvKey == key) {
          setState(() {
            _selectedEnvKey = null;
            _codeController = null;
            _hasUnsavedChanges = false;
          });
        }
        await _loadEnvVars();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  void _showCreateEnvDialog() {
    final keyController = TextEditingController();
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.appSettings_addSecret),
        content: TextField(
          controller: keyController,
          decoration: InputDecoration(
            labelText: l10n.appSettings_secretKey,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () async {
              final key = keyController.text.trim();
              if (key.isNotEmpty) {
                Navigator.pop(context);
                try {
                  final malApi = context.read<MalApi>();
                  await malApi.setEnv(key, "");
                  await _loadEnvVars();
                  _selectEnvVar(key, "");
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              }
            },
            child: Text(l10n.common_create),
          ),
        ],
      ),
    );
  }

  Future<void> _selectEnvVar(String key, String value) async {
    if (_hasUnsavedChanges) {
      final canSwitch = await _promptDiscardChanges();
      if (!canSwitch) return;
    }

    setState(() {
      _selectedFile = null;
      _selectedNode = null;
      _selectedEnvKey = key;
      _hasUnsavedChanges = false;
      _isLoadingFile = false;
      _originalContent = value;

      final controller = CodeController(text: value);
      controller.addListener(() {
        if (!mounted) return;
        final isChanged = controller.text != _originalContent;
        if (_hasUnsavedChanges != isChanged) {
          setState(() {
            _hasUnsavedChanges = isChanged;
          });
        }
      });
      _codeController = controller;
      _fileBytes = null;
      _displayMode = FileDisplayMode.code;
    });
  }

  Widget _buildEnvVarList() {
    if (_isLoadingEnv) {
      return const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) =>
          _showEnvContextMenu(context, details.globalPosition, null),
      child: _envVars.isEmpty
          ? Center(child: Text(context.l10n.appSettings_noSecrets))
          : ListView.builder(
              itemCount: _envVars.length,
              itemBuilder: (context, index) {
                final envVar = _envVars[index];
                final isSelected = _selectedEnvKey == envVar.key;
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onSecondaryTapDown: (details) {
                    _showEnvContextMenu(
                      context,
                      details.globalPosition,
                      envVar.key,
                    );
                  },
                  child: ListTile(
                    title: Text(envVar.key),
                    selected: isSelected,
                    selectedTileColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    onTap: () {
                      _selectEnvVar(envVar.key, envVar.value);
                    },
                  ),
                );
              },
            ),
    );
  }

  Future<void> _selectNode(VfsNode entity) async {
    if (_hasUnsavedChanges &&
        !entity.isDir &&
        entity.path != _selectedFile?.path &&
        _selectedEnvKey == null) {
      final canSwitch = await _promptDiscardChanges();
      if (!canSwitch) return;
    } else if (_hasUnsavedChanges && _selectedEnvKey != null) {
      final canSwitch = await _promptDiscardChanges();
      if (!canSwitch) return;
    }

    setState(() {
      _selectedNode = entity;
      _selectedEnvKey = null;
    });
    if (!entity.isDir) {
      try {
        setState(() {
          _selectedFile = entity;
          _hasUnsavedChanges = false;
          _isLoadingFile = true;
        });
        final malApi = context.read<MalApi>();
        final ext = entity.path.split('.').last.toLowerCase();

        if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
          final bytes = await malApi.freadBytes(entity.path);
          if (mounted) {
            setState(() {
              _fileBytes = bytes;
              _displayMode = FileDisplayMode.image;
              _codeController = null;
              _isLoadingFile = false;
            });
          }
        } else if (ext == 'pdf') {
          final bytes = await malApi.freadBytes(entity.path);
          if (mounted) {
            setState(() {
              _fileBytes = bytes;
              _displayMode = FileDisplayMode.pdf;
              _codeController = null;
              _isLoadingFile = false;
            });
          }
        } else {
          try {
            final content = await malApi.fread(entity.path);
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
                _fileBytes = null;
                _displayMode = FileDisplayMode.code;
                _isLoadingFile = false;
              });
            }
          } catch (e) {
            if (mounted) {
              setState(() {
                _codeController = null;
                _fileBytes = null;
                _displayMode = FileDisplayMode.unsupported;
                _isLoadingFile = false;
              });
            }
          }
        }
      } catch (e) {
        appLogger.error('Error selecting file: $e', tag: 'IdeScreen');
        if (mounted) {
          setState(() {
            _isLoadingFile = false;
            _codeController = null;
            _fileBytes = null;
            _displayMode = FileDisplayMode.unsupported;
          });
        }
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

  void _showEnvContextMenu(
    BuildContext context,
    Offset position,
    String? envKey,
  ) {
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
          value: 'secret',
          child: Row(
            children: [
              const Icon(Icons.vpn_key_outlined, size: 20),
              const SizedBox(width: 8),
              Text(context.l10n.appSettings_addSecret),
            ],
          ),
        ),
        if (envKey != null) ...[
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
      if (value == 'secret') {
        _showCreateEnvDialog();
      } else if (value == 'delete' && envKey != null) {
        _deleteEnvVar(envKey);
      }
    });
  }

  Future<void> _saveCurrentFile() async {
    if (_displayMode == FileDisplayMode.code && _codeController != null) {
      if (_selectedFile != null) {
        try {
          final malApi = context.read<MalApi>();
          await malApi.fwrite(_selectedFile!.path, _codeController!.text);
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
          appLogger.error('Error saving file: $e', tag: 'IdeScreen');
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Failed to save file: $e')));
          }
        }
      } else if (_selectedEnvKey != null) {
        try {
          final malApi = context.read<MalApi>();
          await malApi.setEnv(_selectedEnvKey!, _codeController!.text);
          if (mounted) {
            _originalContent = _codeController!.text;
            setState(() {
              _hasUnsavedChanges = false;
            });
            await _loadEnvVars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${context.l10n.common_save} successful')),
            );
          }
        } catch (e) {
          appLogger.error('Error saving env var: $e', tag: 'IdeScreen');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to save env var: $e')),
            );
          }
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
          final malApi = context.read<MalApi>();
          if (isFile) {
            await malApi.fcreate(path);
          } else {
            await malApi.mkdir(path);
          }
          await _loadFiles();
        } catch (e) {
          appLogger.error('Error creating entity: $e', tag: 'IdeScreen');
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
        final malApi = context.read<MalApi>();
        await malApi.rm(entity.path);
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
        appLogger.error('Error deleting entity: $e', tag: 'IdeScreen');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _handleSidebarDrop(DropDoneDetails details) async {
    String basePath = _drivePath;

    if (_selectedNode != null) {
      if (_selectedNode!.isDir) {
        basePath = _selectedNode!.path;
      } else {
        final parts = _selectedNode!.path.split('/');
        parts.removeLast();
        basePath = parts.join('/');
      }
    }

    await _performDrop(details, basePath);
  }

  Future<void> _handleNodeDrop(DropDoneDetails details, VfsNode node) async {
    String basePath = node.path;
    if (!node.isDir) {
      final parts = node.path.split('/');
      parts.removeLast();
      basePath = parts.join('/');
    }

    await _performDrop(details, basePath);
  }

  Future<void> _performDrop(DropDoneDetails details, String basePath) async {
    final malApi = context.read<MalApi>();

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      for (final file in details.files) {
        if (kDebugMode) {
          print(
            '[IdeScreen] Dropped file: ${file.name}, type: ${file.runtimeType}, path: ${file.path}',
          );
        }
        await _uploadItem(file, basePath, malApi);
      }
      await _loadFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Files uploaded successfully')),
        );
      }
    } catch (e) {
      appLogger.error('Error uploading dropped files: $e', tag: 'IdeScreen');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _dragging = false;
          _hoveredNodePath = null;
        });
      }
    }
  }

  Future<void> _uploadItem(XFile item, String targetPath, MalApi malApi) async {
    final fileName = item.name;
    final path = '$targetPath/$fileName';
    if (kDebugMode) {
      print(
        '[IdeScreen] _uploadItem: name=$fileName path=${item.path} target=$path',
      );
    }
    if (item is DropItemDirectory) {
      if (kDebugMode)
        print('[IdeScreen] detected DropItemDirectory: $fileName');
      if (!await malApi.fexists(path)) {
        await malApi.mkdir(path);
      }
      for (final child in item.children) {
        await _uploadItem(child, path, malApi);
      }
      return;
    }

    if (!kIsWeb) {
      final fileSystemEntity = io.FileSystemEntity.typeSync(item.path);
      if (fileSystemEntity == io.FileSystemEntityType.directory) {
        if (kDebugMode) print('[IdeScreen] detected directory: $fileName');
        if (!await malApi.fexists(path)) {
          await malApi.mkdir(path);
        }
        final dir = io.Directory(item.path);
        await for (final entity in dir.list(recursive: false)) {
          await _uploadItem(XFile(entity.path), path, malApi);
        }
        return;
      }
    }

    final bytes = await item.readAsBytes();
    await malApi.fwriteBytes(path, bytes);
  }

  Widget _buildFileViewer() {
    if (_isLoadingFile) {
      return const Center(child: CircularProgressIndicator());
    } else if (_displayMode == FileDisplayMode.image && _fileBytes != null) {
      return Center(child: InteractiveViewer(child: Image.memory(_fileBytes!)));
    } else if (_displayMode == FileDisplayMode.pdf && _fileBytes != null) {
      return SfPdfViewer.memory(_fileBytes!);
    } else if (_displayMode == FileDisplayMode.unsupported) {
      return const Center(child: Text('Unsupported file format for display'));
    } else if (_displayMode == FileDisplayMode.code &&
        _codeController != null) {
      return Column(
        children: [
          if (_hasUnsavedChanges)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Text(
                context.l10n.ide_unsavedChanges,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: CodeTheme(
              data: CodeThemeData(styles: monokaiSublimeTheme),
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
      );
    }
    return const Center(child: Text('Select a file to edit'));
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
                    } else if (action == 'secret') {
                      _showCreateEnvDialog();
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
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'secret',
                      child: Row(
                        children: [
                          const Icon(Icons.vpn_key_outlined, size: 20),
                          const SizedBox(width: 8),
                          Text(context.l10n.appSettings_addSecret),
                        ],
                      ),
                    ),
                  ],
                ),
                if ((_selectedFile != null || _selectedEnvKey != null) &&
                    _displayMode == FileDisplayMode.code)
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
                      // Left pane: file tree and env vars
                      Expanded(
                        flex: 1,
                        child: DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              const TabBar(
                                tabs: [
                                  Tab(text: 'Files'),
                                  Tab(text: 'Env'),
                                ],
                              ),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    // Files tab
                                    DropTarget(
                                      onDragDone: _handleSidebarDrop,
                                      onDragEntered: (details) {
                                        setState(() {
                                          _dragging = true;
                                        });
                                      },
                                      onDragExited: (details) {
                                        setState(() {
                                          _dragging = false;
                                        });
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: _dragging
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer
                                                    .withValues(alpha: 0.2)
                                              : null,
                                          border: Border(
                                            right: BorderSide(
                                              color: Colors.grey.withValues(
                                                alpha: 0.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.translucent,
                                          onSecondaryTapDown: (details) =>
                                              _showContextMenu(
                                                context,
                                                details.globalPosition,
                                                null,
                                              ),
                                          child: _files.isEmpty
                                              ? const Center(
                                                  child: Text('No files found'),
                                                )
                                              : ListView.builder(
                                                  itemCount: _files.length,
                                                  itemBuilder: (context, index) {
                                                    final entity =
                                                        _files[index];
                                                    final isFile =
                                                        !entity.isDir;
                                                    final relativePath = entity
                                                        .path
                                                        .replaceFirst(
                                                          '$_drivePath/',
                                                          '',
                                                        );
                                                    final isSelected =
                                                        _selectedNode?.path ==
                                                        entity.path;

                                                    // Add padding to simulate folder depth
                                                    final depth =
                                                        relativePath
                                                            .split('/')
                                                            .length -
                                                        1;

                                                    return DropTarget(
                                                      onDragDone: (details) =>
                                                          _handleNodeDrop(
                                                            details,
                                                            entity,
                                                          ),
                                                      onDragEntered:
                                                          (details) => setState(
                                                            () =>
                                                                _hoveredNodePath =
                                                                    entity.path,
                                                          ),
                                                      onDragExited: (details) =>
                                                          setState(
                                                            () =>
                                                                _hoveredNodePath =
                                                                    null,
                                                          ),
                                                      child: GestureDetector(
                                                        behavior:
                                                            HitTestBehavior
                                                                .translucent,
                                                        onSecondaryTapDown:
                                                            (details) {
                                                              _showContextMenu(
                                                                context,
                                                                details
                                                                    .globalPosition,
                                                                entity,
                                                              );
                                                            },
                                                        child: ListTile(
                                                          leading: Padding(
                                                            padding:
                                                                EdgeInsets.only(
                                                                  left:
                                                                      depth *
                                                                      12.0,
                                                                ),
                                                            child: Icon(
                                                              isFile
                                                                  ? Icons
                                                                        .insert_drive_file
                                                                  : Icons
                                                                        .folder,
                                                              size: 20,
                                                              color: isFile
                                                                  ? null
                                                                  : Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .primary,
                                                            ),
                                                          ),
                                                          title: Text(
                                                            relativePath
                                                                .split('/')
                                                                .last,
                                                            style: TextStyle(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  (isSelected &&
                                                                      _hasUnsavedChanges)
                                                                  ? FontWeight
                                                                        .bold
                                                                  : FontWeight
                                                                        .normal,
                                                            ),
                                                          ),
                                                          selected:
                                                              isSelected ||
                                                              _hoveredNodePath ==
                                                                  entity.path,
                                                          selectedTileColor:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .primaryContainer,
                                                          onTap: () {
                                                            _selectNode(entity);
                                                          },
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                        ),
                                      ),
                                    ),
                                    // Env tab
                                    Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          right: BorderSide(
                                            color: Colors.grey.withValues(
                                              alpha: 0.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                      child: _buildEnvVarList(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Right pane: code editor
                      Expanded(
                        flex: 2,
                        child:
                            (_selectedFile == null && _selectedEnvKey == null)
                            ? const Center(
                                child: Text('Select a file or env var to edit'),
                              )
                            : _buildFileViewer(),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

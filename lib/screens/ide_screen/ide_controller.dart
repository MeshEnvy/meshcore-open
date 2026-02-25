import 'dart:io' as io;

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/lua.dart' as highlight_lua;
import 'package:provider/provider.dart';

import '../../services/lua_service.dart';
import '../../services/mal/mal_api.dart';
import '../../services/mal/vfs/vfs.dart';
import '../../utils/app_logger.dart';

enum FileDisplayMode { code, image, pdf, processLogs, unsupported }

/// All IDE state and business logic, exposed as a [ChangeNotifier] so the UI
/// can rebuild reactively without reaching back into the controller.
class IdeController extends ChangeNotifier {
  // ── File tree ───────────────────────────────────────────────────────────────
  String drivePath = '';
  List<VfsNode> files = [];
  VfsNode? selectedNode;
  VfsNode? selectedFile;
  bool isLoading = true;
  bool dragging = false;
  String? hoveredNodePath;

  // ── Editor ──────────────────────────────────────────────────────────────────
  CodeController? codeController;
  String? originalContent;
  FileDisplayMode displayMode = FileDisplayMode.code;
  Uint8List? fileBytes;
  bool isLoadingFile = false;
  bool hasUnsavedChanges = false;

  // ── Env vars ─────────────────────────────────────────────────────────────────
  List<MapEntry<String, String>> envVars = [];
  bool isLoadingEnv = true;
  String? selectedEnvKey;

  // ── Lua task manager ─────────────────────────────────────────────────────────
  LuaProcess? selectedProcess;
  bool showAllProcesses = false;
  final ScrollController logScrollController = ScrollController();

  // ── Internals ────────────────────────────────────────────────────────────────
  final BuildContext _context;

  IdeController(this._context);

  void notify() => notifyListeners();

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  void onLuaServiceUpdated() {
    notify();
    if (displayMode == FileDisplayMode.processLogs &&
        logScrollController.hasClients) {
      final pos = logScrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - 100) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (logScrollController.hasClients) {
            logScrollController.jumpTo(
              logScrollController.position.maxScrollExtent,
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    codeController?.dispose();
    logScrollController.dispose();
    super.dispose();
  }

  // ── Initialization ────────────────────────────────────────────────────────────

  Future<void> init() async {
    try {
      final malApi = _context.read<MalApi>();
      drivePath = malApi.homePath;

      final autoexecPath = '$drivePath/autoexec.lua';
      if (!await malApi.fexists(autoexecPath)) {
        await malApi.fwrite(autoexecPath, 'print("hello world")\n');
      }

      await loadFiles();
      await loadEnvVars();
    } catch (e) {
      appLogger.error('Error initializing IDE: $e', tag: 'IdeController');
      isLoading = false;
      notify();
    }
  }

  // ── File loading ──────────────────────────────────────────────────────────────

  Future<void> loadFiles() async {
    try {
      final malApi = _context.read<MalApi>();
      if (await malApi.fexists(drivePath)) {
        final result = <VfsNode>[];
        Future<void> loadDir(String path) async {
          final children = await malApi.flist(path);
          for (final child in children) {
            result.add(child);
            if (child.isDir) await loadDir(child.path);
          }
        }

        await loadDir(drivePath);
        result.sort((a, b) {
          final aRel = a.path.replaceFirst('$drivePath/', '');
          final bRel = b.path.replaceFirst('$drivePath/', '');
          final aSegs = aRel.split('/');
          final bSegs = bRel.split('/');
          final minLen = aSegs.length < bSegs.length
              ? aSegs.length
              : bSegs.length;
          for (var i = 0; i < minLen; i++) {
            if (aSegs[i] != bSegs[i]) {
              final aIsDir = (i < aSegs.length - 1) || a.isDir;
              final bIsDir = (i < bSegs.length - 1) || b.isDir;
              if (aIsDir && !bIsDir) return -1;
              if (!aIsDir && bIsDir) return 1;
              return aSegs[i].toLowerCase().compareTo(bSegs[i].toLowerCase());
            }
          }
          return aSegs.length.compareTo(bSegs.length);
        });
        files = result;
      }
      isLoading = false;
      notify();
    } catch (e) {
      appLogger.error('Error loading files: $e', tag: 'IdeController');
      isLoading = false;
      notify();
    }
  }

  // ── Node selection ────────────────────────────────────────────────────────────

  Future<void> selectNode(VfsNode entity, BuildContext ctx) async {
    final malApi = ctx.read<MalApi>();
    if (hasUnsavedChanges &&
        !entity.isDir &&
        entity.path != selectedFile?.path &&
        selectedEnvKey == null) {
      if (!await promptDiscardChanges(ctx)) return;
    } else if (hasUnsavedChanges && selectedEnvKey != null) {
      if (!await promptDiscardChanges(ctx)) return;
    }

    selectedNode = entity;
    selectedEnvKey = null;
    notify();

    if (!entity.isDir) {
      selectedFile = entity;
      hasUnsavedChanges = false;
      isLoadingFile = true;
      notify();

      try {
        final ext = entity.path.split('.').last.toLowerCase();

        if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
          final bytes = await malApi.freadBytes(entity.path);
          fileBytes = bytes;
          displayMode = FileDisplayMode.image;
          codeController = null;
          isLoadingFile = false;
          notify();
        } else if (ext == 'pdf') {
          final bytes = await malApi.freadBytes(entity.path);
          fileBytes = bytes;
          displayMode = FileDisplayMode.pdf;
          codeController = null;
          isLoadingFile = false;
          notify();
        } else {
          try {
            final content = await malApi.fread(entity.path);
            originalContent = content;
            final controller = CodeController(
              text: content,
              language: highlight_lua.lua,
            );
            controller.addListener(() {
              final changed = controller.text != originalContent;
              if (hasUnsavedChanges != changed) {
                hasUnsavedChanges = changed;
                notify();
              }
            });
            codeController = controller;
            fileBytes = null;
            displayMode = FileDisplayMode.code;
            isLoadingFile = false;
            notify();
          } catch (_) {
            codeController = null;
            fileBytes = null;
            displayMode = FileDisplayMode.unsupported;
            isLoadingFile = false;
            notify();
          }
        }
      } catch (e) {
        appLogger.error('Error selecting file: $e', tag: 'IdeController');
        isLoadingFile = false;
        codeController = null;
        fileBytes = null;
        displayMode = FileDisplayMode.unsupported;
        notify();
      }
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────────

  Future<void> saveCurrentFile(BuildContext ctx) async {
    if (displayMode != FileDisplayMode.code || codeController == null) return;

    try {
      final malApi = ctx.read<MalApi>();
      if (selectedFile != null) {
        await malApi.fwrite(selectedFile!.path, codeController!.text);
        originalContent = codeController!.text;
        hasUnsavedChanges = false;
        notify();
        if (ctx.mounted) {
          ScaffoldMessenger.of(
            ctx,
          ).showSnackBar(const SnackBar(content: Text('Saved')));
        }
      } else if (selectedEnvKey != null) {
        await malApi.setEnv(selectedEnvKey!, codeController!.text);
        originalContent = codeController!.text;
        hasUnsavedChanges = false;
        notify();
        await loadEnvVars();
        if (ctx.mounted) {
          ScaffoldMessenger.of(
            ctx,
          ).showSnackBar(const SnackBar(content: Text('Saved')));
        }
      }
    } catch (e) {
      appLogger.error('Error saving: $e', tag: 'IdeController');
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  // ── Discard prompt ────────────────────────────────────────────────────────────

  Future<bool> promptDiscardChanges(BuildContext ctx) async {
    if (!hasUnsavedChanges) return true;
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Changes?'),
        content: const Text('You have unsaved changes. Discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () async {
              await saveCurrentFile(ctx);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  // ── Delete ────────────────────────────────────────────────────────────────────

  Future<void> deleteEntity(VfsNode entity, BuildContext ctx) async {
    final isFile = !entity.isDir;
    final relativePath = entity.path.replaceFirst('$drivePath/', '');

    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: Text(
          isFile
              ? 'Delete file "$relativePath"?'
              : 'Delete directory "$relativePath" and all its contents?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!ctx.mounted) return;

    try {
      final malApi = ctx.read<MalApi>();
      await malApi.rm(entity.path);
      if (selectedFile?.path == entity.path ||
          (!isFile &&
              selectedFile?.path.startsWith('${entity.path}/') == true)) {
        selectedFile = null;
        codeController = null;
        hasUnsavedChanges = false;
      }
      if (selectedNode?.path == entity.path ||
          (!isFile &&
              selectedNode?.path.startsWith('${entity.path}/') == true)) {
        selectedNode = null;
      }
      notify();
      await loadFiles();
    } catch (e) {
      appLogger.error('Error deleting: $e', tag: 'IdeController');
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Create ────────────────────────────────────────────────────────────────────

  Future<void> createEntity({
    required bool isFile,
    required BuildContext ctx,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: Text(isFile ? 'New File' : 'New Directory'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: isFile ? 'File Name' : 'Directory Name',
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (value == null || value.trim().isEmpty) return;
    if (!ctx.mounted) return;

    String basePath = drivePath;
    if (selectedNode != null) {
      basePath = selectedNode!.isDir
          ? selectedNode!.path
          : (selectedNode!.path.split('/')..removeLast()).join('/');
    }
    final path = '$basePath/${value.trim()}';

    try {
      final malApi = ctx.read<MalApi>();
      if (isFile) {
        await malApi.fcreate(path);
      } else {
        await malApi.mkdir(path);
      }
      await loadFiles();
    } catch (e) {
      appLogger.error('Error creating: $e', tag: 'IdeController');
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Env vars ──────────────────────────────────────────────────────────────────

  Future<void> loadEnvVars() async {
    isLoadingEnv = true;
    notify();
    try {
      final malApi = _context.read<MalApi>();
      final keys = await malApi.getKeys(scope: 'env');
      final vars = <MapEntry<String, String>>[];
      for (final key in keys) {
        if (!key.startsWith('vfs:')) {
          vars.add(MapEntry(key, await malApi.getEnv(key) ?? ''));
        }
      }
      vars.sort((a, b) => a.key.compareTo(b.key));
      envVars = vars;
      isLoadingEnv = false;
      notify();
    } catch (e) {
      appLogger.error('Error loading env vars: $e', tag: 'IdeController');
      isLoadingEnv = false;
      notify();
    }
  }

  Future<void> selectEnvVar(String key, String value) async {
    if (hasUnsavedChanges) {
      if (!await promptDiscardChanges(_context)) return;
    }
    selectedFile = null;
    selectedNode = null;
    selectedEnvKey = key;
    hasUnsavedChanges = false;
    isLoadingFile = false;
    originalContent = value;
    final ctrl = CodeController(text: value);
    ctrl.addListener(() {
      final changed = ctrl.text != originalContent;
      if (hasUnsavedChanges != changed) {
        hasUnsavedChanges = changed;
        notify();
      }
    });
    codeController = ctrl;
    fileBytes = null;
    displayMode = FileDisplayMode.code;
    notify();
  }

  Future<void> deleteEnvVar(String key, BuildContext ctx) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Variable'),
        content: Text('Delete variable "$key"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!ctx.mounted) return;
    try {
      final malApi = ctx.read<MalApi>();
      await malApi.deleteKey(key, scope: 'env');
      if (selectedEnvKey == key) {
        selectedEnvKey = null;
        codeController = null;
        hasUnsavedChanges = false;
      }
      notify();
      await loadEnvVars();
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> createEnvVar(String key, BuildContext ctx) async {
    try {
      final malApi = ctx.read<MalApi>();
      await malApi.setEnv(key, '');
      await loadEnvVars();
      await selectEnvVar(key, '');
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Lua process ───────────────────────────────────────────────────────────────

  Future<void> selectProcess(
    LuaProcess? process, {
    bool showAll = false,
  }) async {
    if (hasUnsavedChanges) {
      if (!await promptDiscardChanges(_context)) return;
    }
    selectedNode = null;
    selectedFile = null;
    selectedEnvKey = null;
    codeController = null;
    hasUnsavedChanges = false;
    isLoadingFile = false;
    selectedProcess = process;
    showAllProcesses = showAll;
    displayMode = FileDisplayMode.processLogs;
    notify();
  }

  // ── Drag & drop ───────────────────────────────────────────────────────────────

  Future<void> performDrop(DropDoneDetails details, String basePath) async {
    final malApi = _context.read<MalApi>();
    isLoading = true;
    notify();
    try {
      for (final file in details.files) {
        await _uploadItem(file, basePath, malApi);
      }
      await loadFiles();
    } catch (e) {
      appLogger.error('Drop upload error: $e', tag: 'IdeController');
    } finally {
      isLoading = false;
      dragging = false;
      hoveredNodePath = null;
      notify();
    }
  }

  Future<void> _uploadItem(XFile item, String targetPath, MalApi malApi) async {
    final path = '$targetPath/${item.name}';
    if (item is DropItemDirectory) {
      if (!await malApi.fexists(path)) await malApi.mkdir(path);
      for (final child in item.children) {
        await _uploadItem(child, path, malApi);
      }
      return;
    }
    if (!kIsWeb) {
      final type = io.FileSystemEntity.typeSync(item.path);
      if (type == io.FileSystemEntityType.directory) {
        if (!await malApi.fexists(path)) await malApi.mkdir(path);
        final dir = io.Directory(item.path);
        await for (final entity in dir.list(recursive: false)) {
          await _uploadItem(XFile(entity.path), path, malApi);
        }
        return;
      }
    }
    await malApi.fwriteBytes(path, await item.readAsBytes());
  }

  // ── Run Lua script ────────────────────────────────────────────────────────────

  Future<void> runCurrentScript(BuildContext ctx) async {
    final file = selectedFile;
    if (file == null || codeController == null) return;
    if (!ctx.mounted) return;
    final malApi = ctx.read<MalApi>();
    final content = codeController!.text;
    final fileName = file.path.split('/').last;
    await LuaService().runScript(malApi, content, name: fileName);
    await selectProcess(null, showAll: false);
  }

  Future<void> runScript(VfsNode entity, BuildContext ctx) async {
    if (!ctx.mounted) return;
    try {
      final malApi = ctx.read<MalApi>();
      final content = await malApi.fread(entity.path);
      final fileName = entity.path.split('/').last;
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('Started $fileName')));
      }
      await LuaService().runScript(malApi, content, name: fileName);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

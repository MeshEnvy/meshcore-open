import 'dart:io';
import 'package:flutter/material.dart';
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
  File? _selectedFile;
  CodeController? _codeController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initDriveDirs();
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
        if (mounted) {
          setState(() {
            _files = files.whereType<File>().toList();
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

  Future<void> _selectFile(File file) async {
    try {
      setState(() {
        _selectedFile = file;
      });
      final content = await file.readAsString();
      if (mounted) {
        setState(() {
          _codeController = CodeController(
            text: content,
            language: highlight_lua.lua,
          );
        });
      }
    } catch (e) {
      debugPrint('Error selecting file: $e');
    }
  }

  Future<void> _saveCurrentFile() async {
    if (_selectedFile != null && _codeController != null) {
      try {
        await _selectedFile!.writeAsString(_codeController!.text);
        if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.appSettings_ide),
        actions: [
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
                        right: BorderSide(color: Colors.grey.withOpacity(0.5)),
                      ),
                    ),
                    child: _files.isEmpty
                        ? const Center(child: Text('No files found'))
                        : ListView.builder(
                            itemCount: _files.length,
                            itemBuilder: (context, index) {
                              final file = _files[index] as File;
                              final relativePath = file.path.replaceFirst(
                                '$_drivePath/',
                                '',
                              );
                              final isSelected =
                                  _selectedFile?.path == file.path;

                              return ListTile(
                                leading: const Icon(
                                  Icons.insert_drive_file,
                                  size: 20,
                                ),
                                title: Text(
                                  relativePath,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                selected: isSelected,
                                selectedTileColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                onTap: () => _selectFile(file),
                              );
                            },
                          ),
                  ),
                ),
                // Right pane: code editor
                Expanded(
                  flex: 2,
                  child: _selectedFile == null || _codeController == null
                      ? const Center(child: Text('Select a file to edit'))
                      : CodeTheme(
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
            ),
    );
  }
}

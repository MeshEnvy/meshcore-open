import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../services/mal/mal_api.dart';

class EnvVarsScreen extends StatefulWidget {
  const EnvVarsScreen({super.key});

  @override
  State<EnvVarsScreen> createState() => _EnvVarsScreenState();
}

class _EnvVarsScreenState extends State<EnvVarsScreen> {
  bool _isLoading = true;
  List<MapEntry<String, String>> _envVars = [];
  late MalApi _malApi;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _malApi = Provider.of<MalApi>(context, listen: false);
      _loadEnvVars();
    });
  }

  Future<void> _loadEnvVars() async {
    setState(() => _isLoading = true);
    try {
      final keys = await _malApi.getKeys(scope: 'env');
      final List<MapEntry<String, String>> vars = [];

      for (final key in keys) {
        // Only show variables that are NOT part of the VFS internal storage
        if (!key.startsWith('vfs:')) {
          final value = await _malApi.getEnv(key) ?? '';
          vars.add(MapEntry(key, value));
        }
      }

      // Sort alphabetically by key
      vars.sort((a, b) => a.key.compareTo(b.key));

      setState(() {
        _envVars = vars;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading variables: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveEnvVar(String key, String value) async {
    if (key.isEmpty) return;
    try {
      await _malApi.setEnv(key, value);
      await _loadEnvVars(); // Refresh list
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving variable: $e')));
      }
    }
  }

  Future<void> _deleteEnvVar(String key) async {
    try {
      await _malApi.deleteKey(key, scope: 'env');
      await _loadEnvVars(); // Refresh list
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting variable: $e')));
      }
    }
  }

  void _showEditDialog([MapEntry<String, String>? existingVar]) {
    final l10n = context.l10n;
    final isEditing = existingVar != null;
    final keyController = TextEditingController(text: existingVar?.key ?? '');
    final valueController = TextEditingController(
      text: existingVar?.value ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isEditing ? l10n.appSettings_editSecret : l10n.appSettings_addSecret,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: InputDecoration(
                labelText: l10n.appSettings_secretKey,
                border: const OutlineInputBorder(),
              ),
              enabled: !isEditing, // Don't allow changing key if editing
            ),
            const SizedBox(height: 16),
            TextField(
              controller: valueController,
              decoration: InputDecoration(
                labelText: l10n.appSettings_secretValue,
                border: const OutlineInputBorder(),
              ),
              maxLines: null,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () {
              final key = keyController.text.trim();
              final value = valueController.text.trim();
              if (key.isNotEmpty) {
                _saveEnvVar(key, value);
                Navigator.pop(context);
              }
            },
            child: Text(l10n.common_save),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String key) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.appSettings_deleteSecretTitle),
        content: Text(l10n.appSettings_deleteSecretConfirm(key)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () {
              _deleteEnvVar(key);
              Navigator.pop(context);
            },
            child: Text(
              l10n.common_delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: AdaptiveAppBarTitle(l10n.appSettings_secrets),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _envVars.isEmpty
          ? Center(
              child: Text(
                l10n.appSettings_noSecrets,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
            )
          : ListView.separated(
              itemCount: _envVars.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final envVar = _envVars[index];
                return ListTile(
                  title: Text(
                    envVar.key,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    envVar.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _showEditDialog(envVar),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => _confirmDelete(envVar.key),
                      ),
                    ],
                  ),
                  onTap: () => _showEditDialog(envVar),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

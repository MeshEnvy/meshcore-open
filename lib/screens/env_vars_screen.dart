import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../widgets/adaptive_app_bar_title.dart';

class EnvVarsScreen extends StatefulWidget {
  const EnvVarsScreen({super.key});

  @override
  State<EnvVarsScreen> createState() => _EnvVarsScreenState();
}

class _EnvVarsScreenState extends State<EnvVarsScreen> {
  static const String _secretPrefix = 'secret:';
  late SharedPreferences _prefs;
  bool _isLoading = true;
  List<MapEntry<String, String>> _secrets = [];

  @override
  void initState() {
    super.initState();
    _loadSecrets();
  }

  Future<void> _loadSecrets() async {
    _prefs = await SharedPreferences.getInstance();
    final keys = _prefs.getKeys().where((k) => k.startsWith(_secretPrefix));
    final secrets = keys.map((k) {
      final keyWithoutPrefix = k.substring(_secretPrefix.length);
      final value = _prefs.getString(k) ?? '';
      return MapEntry(keyWithoutPrefix, value);
    }).toList();

    // Sort alphabetically by key
    secrets.sort((a, b) => a.key.compareTo(b.key));

    setState(() {
      _secrets = secrets;
      _isLoading = false;
    });
  }

  Future<void> _saveSecret(String key, String value) async {
    if (key.isEmpty) return;
    await _prefs.setString('$_secretPrefix$key', value);
    await _loadSecrets(); // Refresh list
  }

  Future<void> _deleteSecret(String key) async {
    await _prefs.remove('$_secretPrefix$key');
    await _loadSecrets(); // Refresh list
  }

  void _showEditDialog([MapEntry<String, String>? existingSecret]) {
    final isEditing = existingSecret != null;
    final keyController = TextEditingController(
      text: existingSecret?.key ?? '',
    );
    final valueController = TextEditingController(
      text: existingSecret?.value ?? '',
    );
    final l10n = context.l10n;

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
                _saveSecret(key, value);
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
              _deleteSecret(key);
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
          : _secrets.isEmpty
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
              itemCount: _secrets.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final secret = _secrets[index];
                return ListTile(
                  title: Text(
                    secret.key,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    secret.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _showEditDialog(secret),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => _confirmDelete(secret.key),
                      ),
                    ],
                  ),
                  onTap: () => _showEditDialog(secret),
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

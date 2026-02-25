import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../services/mal/mal_api.dart';
import '../../../utils/app_logger.dart';
import 'ai_context_builder.dart';
import 'mesh_api_prompt.dart';

// ── KV keys ──────────────────────────────────────────────────────────────────

const _kScope = 'ide.ai';
const _kKeyEndpoint = 'endpoint';
const _kKeyModel = 'model';
const _kKeyEnabled = 'enabled';
const _kKeyPaneWidth = 'pane_width';

const _kDefaultEndpoint = 'http://localhost:11434';
const _kDefaultModel = 'qwen2.5-coder:7b';
const _kDefaultPaneWidth = 320.0;

// ── Status ────────────────────────────────────────────────────────────────────

enum AiConnectionStatus {
  unchecked,
  checking,
  connected,
  disconnected,
  modelMissing,
}

// ── Chat message ──────────────────────────────────────────────────────────────

class AiChatMessage {
  final bool isUser;
  final String text;
  final DateTime timestamp;

  const AiChatMessage({
    required this.isUser,
    required this.text,
    required this.timestamp,
  });

  AiChatMessage copyWith({String? text}) => AiChatMessage(
    isUser: isUser,
    text: text ?? this.text,
    timestamp: timestamp,
  );
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Manages Ollama connectivity, preferences (persisted via MAL KV),
/// and the chat history for the IDE AI Assistant pane.
class AiAssistantService extends ChangeNotifier {
  // ── Preferences ─────────────────────────────────────────────────────────────
  String endpoint = _kDefaultEndpoint;
  String model = _kDefaultModel;
  bool enabled = true;
  double paneWidth = _kDefaultPaneWidth;

  // ── Runtime state ────────────────────────────────────────────────────────────
  AiConnectionStatus connectionStatus = AiConnectionStatus.unchecked;

  /// Models detected from the Ollama /api/tags endpoint.
  List<String> availableModels = [];

  /// Whether the preferred model is actually available.
  bool get modelAvailable =>
      availableModels.isEmpty || availableModels.contains(model);

  // ── Chat ─────────────────────────────────────────────────────────────────────
  final List<AiChatMessage> messages = [];
  bool isGenerating = false;

  // ── Internals ────────────────────────────────────────────────────────────────
  MalApi? _malApi;
  http.Client _httpClient = http.Client();

  // ── Init ─────────────────────────────────────────────────────────────────────

  Future<void> init(MalApi malApi) async {
    _malApi = malApi;
    await Future.wait([_loadPreferences(), MeshApiPrompt.load()]);
  }

  Future<void> _loadPreferences() async {
    final mal = _malApi;
    if (mal == null) return;
    try {
      endpoint =
          await mal.getKey(_kKeyEndpoint, scope: _kScope) ?? _kDefaultEndpoint;
      model = await mal.getKey(_kKeyModel, scope: _kScope) ?? _kDefaultModel;
      final enabledStr =
          await mal.getKey(_kKeyEnabled, scope: _kScope) ?? 'true';
      enabled = enabledStr != 'false';
      final widthStr = await mal.getKey(_kKeyPaneWidth, scope: _kScope);
      paneWidth = widthStr != null
          ? double.tryParse(widthStr) ?? _kDefaultPaneWidth
          : _kDefaultPaneWidth;
    } catch (e) {
      appLogger.error('Failed to load AI preferences: $e', tag: 'AiService');
    }
    notifyListeners();
  }

  Future<void> savePreferences() async {
    final mal = _malApi;
    if (mal == null) return;
    try {
      await mal.setKey(_kKeyEndpoint, endpoint, scope: _kScope);
      await mal.setKey(_kKeyModel, model, scope: _kScope);
      await mal.setKey(
        _kKeyEnabled,
        enabled ? 'true' : 'false',
        scope: _kScope,
      );
      await mal.setKey(
        _kKeyPaneWidth,
        paneWidth.toStringAsFixed(1),
        scope: _kScope,
      );
    } catch (e) {
      appLogger.error('Failed to save AI preferences: $e', tag: 'AiService');
    }
  }

  // ── Connection test ───────────────────────────────────────────────────────────

  Future<void> testConnection() async {
    connectionStatus = AiConnectionStatus.checking;
    availableModels = [];
    notifyListeners();

    try {
      final uri = Uri.parse('${_normalizedEndpoint()}/api/tags');
      final response = await _httpClient
          .get(uri)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final models =
            (data['models'] as List?)
                ?.map(
                  (m) => (m as Map<String, dynamic>)['name'] as String? ?? '',
                )
                .where((n) => n.isNotEmpty)
                .toList() ??
            [];
        availableModels = models;

        // Check the configured model is actually available.
        if (models.contains(model)) {
          connectionStatus = AiConnectionStatus.connected;
          appLogger.info(
            'Ollama connected. Model "$model" available.',
            tag: 'AiService',
          );
        } else {
          connectionStatus = AiConnectionStatus.modelMissing;
          appLogger.warn(
            'Ollama connected but model "$model" not found. '
            'Available: $models',
            tag: 'AiService',
          );
        }
      } else {
        connectionStatus = AiConnectionStatus.disconnected;
      }
    } catch (e) {
      connectionStatus = AiConnectionStatus.disconnected;
      appLogger.error('Ollama connection test failed: $e', tag: 'AiService');
    }
    notifyListeners();
  }

  // ── Chat ─────────────────────────────────────────────────────────────────────

  /// Sends [userMessage] to the model, optionally enriching context with
  /// the current script and diagnostic information from [contextBuilder].
  ///
  /// Streams the response into the last [AiChatMessage] in [messages].
  Future<void> sendMessage(
    String userMessage, {
    AiContextBuilder? contextBuilder,
  }) async {
    if (isGenerating) return;

    final userMsg = AiChatMessage(
      isUser: true,
      text: userMessage,
      timestamp: DateTime.now(),
    );
    messages.add(userMsg);

    final assistantMsg = AiChatMessage(
      isUser: false,
      text: '',
      timestamp: DateTime.now(),
    );
    messages.add(assistantMsg);
    isGenerating = true;
    notifyListeners();

    try {
      final fullPrompt = contextBuilder != null
          ? contextBuilder.buildPrompt(userMessage)
          : userMessage;

      final buffer = StringBuffer();
      await for (final chunk in _streamGenerate(fullPrompt)) {
        buffer.write(chunk);
        // Update the last message in place
        messages[messages.length - 1] = assistantMsg.copyWith(
          text: buffer.toString(),
        );
        notifyListeners();
      }
    } catch (e) {
      messages[messages.length - 1] = assistantMsg.copyWith(
        text: '⚠️ Error: ${e.toString()}',
      );
      appLogger.error('AI generation failed: $e', tag: 'AiService');
    } finally {
      isGenerating = false;
      notifyListeners();
    }
  }

  /// Fires a quick-action prompt (Fix, Explain, etc.) with full context.
  Future<void> quickAction(
    String actionPrompt, {
    required AiContextBuilder contextBuilder,
  }) => sendMessage(actionPrompt, contextBuilder: contextBuilder);

  void clearHistory() {
    messages.clear();
    notifyListeners();
  }

  // ── Streaming ─────────────────────────────────────────────────────────────────

  Stream<String> _streamGenerate(String prompt) async* {
    final uri = Uri.parse('${_normalizedEndpoint()}/api/generate');
    final body = jsonEncode({
      'model': model,
      'system': MeshApiPrompt.systemPrompt,
      'prompt': prompt,
      'stream': true,
    });

    // Replace the client so each generation can be cancelled cleanly.
    _httpClient.close();
    _httpClient = http.Client();

    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = body;

    final streamedResponse = await _httpClient
        .send(request)
        .timeout(const Duration(seconds: 30));

    // Surface non-200 responses as actionable errors rather than
    // silently yielding nothing while the spinner keeps spinning.
    if (streamedResponse.statusCode != 200) {
      final errorBody = await streamedResponse.stream
          .transform(utf8.decoder)
          .join();
      if (streamedResponse.statusCode == 404) {
        throw Exception(
          'Model "$model" not found on Ollama.\n'
          'Run:  ollama pull $model',
        );
      }
      throw Exception(
        'Ollama returned ${streamedResponse.statusCode}: '
        '${errorBody.trim().isNotEmpty ? errorBody.trim() : "unknown error"}',
      );
    }

    await for (final chunk
        in streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (chunk.isEmpty) continue;
      try {
        final data = jsonDecode(chunk) as Map<String, dynamic>;
        // Ollama can surface errors mid-stream too (e.g. context exceeded).
        if (data.containsKey('error')) {
          throw Exception('Ollama: ${data['error']}');
        }
        final token = data['response'] as String? ?? '';
        if (token.isNotEmpty) yield token;
        if (data['done'] == true) break;
      } catch (e) {
        if (e is Exception) rethrow; // propagate structured errors
        // Malformed JSON chunk — skip silently
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String _normalizedEndpoint() {
    // Strip trailing slash
    return endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }

  // ── Computed UI helpers ───────────────────────────────────────────────────────

  /// True only when Ollama is reachable AND the configured model is available.
  bool get isConnected => connectionStatus == AiConnectionStatus.connected;

  /// True when Ollama responds but the configured model isn't pulled yet.
  bool get isModelMissing =>
      connectionStatus == AiConnectionStatus.modelMissing;

  bool get isChecking => connectionStatus == AiConnectionStatus.checking;

  String get statusLabel {
    switch (connectionStatus) {
      case AiConnectionStatus.unchecked:
        return 'Not tested';
      case AiConnectionStatus.checking:
        return 'Connecting…';
      case AiConnectionStatus.connected:
        return 'Connected · $model';
      case AiConnectionStatus.disconnected:
        return 'Not connected';
      case AiConnectionStatus.modelMissing:
        return 'Model not found';
    }
  }
}

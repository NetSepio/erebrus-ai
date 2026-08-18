import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'node_discovery_service.dart';

class NetworkInferenceException implements Exception {
  const NetworkInferenceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Streams OpenAI-compatible completions from another Erebrus node on LAN.
class NetworkInferenceService extends ChangeNotifier {
  NetworkInferenceService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  static final NetworkInferenceService _instance = NetworkInferenceService();
  static NetworkInferenceService get instance => _instance;

  http.Client _client;
  final bool _ownsClient;
  bool _isGenerating = false;

  bool get isGenerating => _isGenerating;

  Stream<String> generate({
    required NetworkModelTarget target,
    required String prompt,
    String systemPrompt = '',
    int maxOutputTokens = 768,
    double temperature = 0.7,
    double topP = 0.9,
    double repeatPenalty = 1.1,
    List<String> stop = const [],
  }) async* {
    if (_isGenerating) {
      throw const NetworkInferenceException(
        'Another network response is already being generated.',
      );
    }
    if (target.accessToken.isEmpty) {
      throw const NetworkInferenceException(
        'This node was discovered without a LAN access token. Update Erebrus AI on the serving device, restart LAN sharing, then rescan.',
      );
    }

    _isGenerating = true;
    notifyListeners();
    try {
      final request = http.Request('POST', target.chatCompletionsUri)
        ..headers['accept'] = 'text/event-stream'
        ..headers['content-type'] = 'application/json'
        ..headers['authorization'] = 'Bearer ${target.accessToken}'
        ..body = jsonEncode({
          'model': target.modelId,
          'stream': true,
          'messages': [
            if (systemPrompt.trim().isNotEmpty)
              {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': maxOutputTokens,
          'temperature': temperature,
          'top_p': topP,
          'repeat_penalty': repeatPenalty,
          if (stop.isNotEmpty) 'stop': stop,
        });
      final response = await _client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        throw NetworkInferenceException(
          _errorMessage(body) ??
              'The node returned HTTP ${response.statusCode}.',
        );
      }

      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        final decoded = jsonDecode(data);
        if (decoded is! Map) continue;
        final error = decoded['error'];
        if (error is Map) {
          throw NetworkInferenceException(
            error['message']?.toString() ?? 'Network inference failed.',
          );
        }
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty || choices.first is! Map) {
          continue;
        }
        final choice = choices.first as Map;
        final delta = choice['delta'];
        final message = choice['message'];
        final content = delta is Map
            ? delta['content']?.toString()
            : message is Map
            ? message['content']?.toString()
            : null;
        if (content != null && content.isNotEmpty) yield content;
      }
    } on NetworkInferenceException {
      rethrow;
    } on Object catch (error) {
      throw NetworkInferenceException(
        'Could not reach ${target.nodeName}: $error',
      );
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    if (!_isGenerating) return;
    _client.close();
    if (_ownsClient) _client = http.Client();
    _isGenerating = false;
    notifyListeners();
  }

  static String? _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        return (decoded['error'] as Map)['message']?.toString();
      }
    } on FormatException {
      // The HTTP status below remains more useful than an HTML/plain response.
    }
    return null;
  }
}

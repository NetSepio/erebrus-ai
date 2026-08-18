import 'dart:convert';

import 'package:erebrus_ai/services/network_inference_service.dart';
import 'package:erebrus_ai/services/node_discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const target = NetworkModelTarget(
    nodeId: 'mac-node',
    nodeName: 'Studio Mac',
    host: '192.168.1.24',
    port: 11434,
    accessToken: 'lan-token',
    modelId: 'bonsai-4b',
    modelName: 'Bonsai 4B',
  );

  test('streams authenticated completion chunks from a LAN node', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        [
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': 'Hello '},
              },
            ],
          })}',
          '',
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': 'from Mac'},
              },
            ],
          })}',
          '',
          'data: [DONE]',
          '',
        ].join('\n'),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final service = NetworkInferenceService(client: client);

    final result = await service
        .generate(target: target, prompt: 'Hi', systemPrompt: 'Be concise')
        .join();

    expect(result, 'Hello from Mac');
    expect(captured.method, 'POST');
    expect(captured.url.path, '/v1/chat/completions');
    expect(captured.headers['authorization'], 'Bearer lan-token');
    final payload = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(payload['model'], 'bonsai-4b');
    expect(payload['stream'], isTrue);
    expect((payload['messages'] as List).last['content'], 'Hi');
    expect(service.isGenerating, isFalse);
  });

  test(
    'surfaces a server inference error instead of a download prompt',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'Model is busy'},
          }),
          503,
        ),
      );
      final service = NetworkInferenceService(client: client);

      await expectLater(
        service.generate(target: target, prompt: 'Hi'),
        emitsError(
          isA<NetworkInferenceException>().having(
            (error) => error.message,
            'message',
            'Model is busy',
          ),
        ),
      );
    },
  );
}

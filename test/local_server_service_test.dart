import 'dart:convert';
import 'dart:io';

import 'package:erebrus_ai/services/local_server_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('isPublicLocalServerMetadataRequest', () {
    test('only GET health is public', () {
      expect(isPublicLocalServerMetadataRequest('GET', 'health'), isTrue);
      expect(isPublicLocalServerMetadataRequest('GET', 'v1/models'), isFalse);
      expect(
        isPublicLocalServerMetadataRequest('POST', 'v1/chat/completions'),
        isFalse,
      );
      expect(isPublicLocalServerMetadataRequest('POST', 'health'), isFalse);
      expect(isPublicLocalServerMetadataRequest('DELETE', 'health'), isFalse);
    });
  });

  group('LocalServerService', () {
    test('singleton instance exists and defaults to stopped', () {
      final service = LocalServerService.instance;
      expect(service, isNotNull);
      expect(service.isRunning, isFalse);
      expect(service.baseUrl, isNull);
      expect(service.sharedModelIds, isEmpty);
    });

    test('generates an API key with ere_sk_ prefix', () async {
      final service = LocalServerService.instance;
      final key = await service.apiKey;
      expect(key, startsWith('ere_sk_'));
      expect(key.length, greaterThan(10));

      // Subsequent calls return the same cached key
      final cached = await service.apiKey;
      expect(cached, equals(key));
    });
  });

  group('local server API-key persistence', () {
    test(
      'falls back to durable preferences when secure storage fails',
      () async {
        String? fallback;

        final first = await loadOrCreateLocalServerApiKey(
          secureRead: () => throw StateError('secure storage unavailable'),
          secureWrite: (_) => throw StateError('secure storage unavailable'),
          fallbackRead: () async => fallback,
          fallbackWrite: (value) async => fallback = value,
          fallbackDelete: () async => fallback = null,
          generate: () => 'ere_sk_generated',
        );
        final second = await loadOrCreateLocalServerApiKey(
          secureRead: () => throw StateError('secure storage unavailable'),
          secureWrite: (_) => throw StateError('secure storage unavailable'),
          fallbackRead: () async => fallback,
          fallbackWrite: (value) async => fallback = value,
          fallbackDelete: () async => fallback = null,
          generate: () => 'ere_sk_rotated',
        );

        expect(first, 'ere_sk_generated');
        expect(second, first);
        expect(fallback, first);
      },
    );

    test(
      'migrates a fallback key only after secure persistence succeeds',
      () async {
        String? secure;
        String? fallback = 'ere_sk_legacy';

        final key = await loadOrCreateLocalServerApiKey(
          secureRead: () async => secure,
          secureWrite: (value) async => secure = value,
          fallbackRead: () async => fallback,
          fallbackWrite: (value) async => fallback = value,
          fallbackDelete: () async => fallback = null,
          generate: () => 'unused',
        );

        expect(key, 'ere_sk_legacy');
        expect(secure, key);
        expect(fallback, isNull);
      },
    );
  });

  group('bounded local server request bodies', () {
    test('rejects a chunked body after it crosses the byte limit', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:11434/v1/chat/completions'),
        body: Stream<List<int>>.fromIterable([
          [1, 2, 3],
          [4, 5, 6],
        ]),
      );

      await expectLater(
        readBoundedLocalServerBody(request, maxBytes: 5),
        throwsA(isA<LocalServerPayloadTooLarge>()),
      );
    });

    test('decodes an in-limit chunked UTF-8 body', () async {
      final encoded = utf8.encode('{"prompt":"hello"}');
      final request = Request(
        'POST',
        Uri.parse('http://localhost:11434/v1/chat/completions'),
        body: Stream<List<int>>.fromIterable([
          encoded.sublist(0, 4),
          encoded.sublist(4),
        ]),
      );

      expect(
        await readBoundedLocalServerBody(request, maxBytes: encoded.length),
        utf8.decode(encoded),
      );
    });
  });

  group('Local server shelf pipeline handlers', () {
    const testApiKey = 'ere_sk_test_secret_key_12345';
    const testLanToken = 'ere_lan_temporary_token_67890';

    Handler buildTestPipeline({
      String apiKey = testApiKey,
      String? lanAccessToken = testLanToken,
    }) {
      // Replicate the pipeline defined in LocalServerService
      Future<Response> router(Request request) async {
        final path = request.url.path;
        final method = request.method;

        if (method == 'GET' && path == 'health') {
          return Response.ok(
            json.encode({
              'status': 'ok',
              'name': 'Erebrus AI',
              'version': '1.0.0',
              'inference_ready': true,
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        if (method == 'GET' && path == 'v1/models') {
          return Response.ok(
            json.encode({'object': 'list', 'data': []}),
            headers: {'content-type': 'application/json'},
          );
        }

        return Response.notFound('Not found');
      }

      final pipeline = const Pipeline()
          .addMiddleware(
            (Handler inner) => (Request request) async {
              // Rate limit check
              if (request.contentLength != null &&
                  request.contentLength! > 10 * 1024 * 1024) {
                return Response(
                  413,
                  body: json.encode({
                    'error': {
                      'message': 'Payload too large',
                      'type': 'payload_too_large',
                    },
                  }),
                  headers: {'content-type': 'application/json'},
                );
              }
              return inner(request);
            },
          )
          .addMiddleware(
            (Handler inner) => (Request request) async {
              if (isPublicLocalServerMetadataRequest(
                request.method,
                request.url.path,
              )) {
                return inner(request);
              }
              final auth = request.headers['authorization'] ?? '';
              final token = auth.startsWith('Bearer ')
                  ? auth.substring(7).trim()
                  : '';
              if (token != apiKey && token != lanAccessToken) {
                return Response.unauthorized(
                  json.encode({
                    'error': {
                      'message': 'Invalid API key',
                      'type': 'authentication_error',
                    },
                  }),
                );
              }
              return inner(request);
            },
          )
          .addHandler(router);

      return pipeline;
    }

    test('GET health is accessible without authentication', () async {
      final handler = buildTestPipeline();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:11434/health'),
      );
      final response = await handler(request);

      expect(response.statusCode, equals(HttpStatus.ok));
      final body = json.decode(await response.readAsString());
      expect(body['status'], equals('ok'));
      expect(body['inference_ready'], isTrue);
    });

    test('GET v1/models requires valid authorization header', () async {
      final handler = buildTestPipeline();

      // No auth header -> 401
      final unauthRequest = Request(
        'GET',
        Uri.parse('http://localhost:11434/v1/models'),
      );
      final unauthResponse = await handler(unauthRequest);
      expect(unauthResponse.statusCode, equals(HttpStatus.unauthorized));

      // Invalid token -> 401
      final badTokenRequest = Request(
        'GET',
        Uri.parse('http://localhost:11434/v1/models'),
        headers: {'authorization': 'Bearer invalid_wrong_token'},
      );
      final badTokenResponse = await handler(badTokenRequest);
      expect(badTokenResponse.statusCode, equals(HttpStatus.unauthorized));

      // Valid API key -> 200
      final validKeyRequest = Request(
        'GET',
        Uri.parse('http://localhost:11434/v1/models'),
        headers: {'authorization': 'Bearer $testApiKey'},
      );
      final validKeyResponse = await handler(validKeyRequest);
      expect(validKeyResponse.statusCode, equals(HttpStatus.ok));

      // Valid LAN token -> 200
      final validLanRequest = Request(
        'GET',
        Uri.parse('http://localhost:11434/v1/models'),
        headers: {'authorization': 'Bearer $testLanToken'},
      );
      final validLanResponse = await handler(validLanRequest);
      expect(validLanResponse.statusCode, equals(HttpStatus.ok));
    });

    test('oversized payload is rejected with HTTP 413', () async {
      final handler = buildTestPipeline();
      final oversizedRequest = Request(
        'POST',
        Uri.parse('http://localhost:11434/v1/chat/completions'),
        headers: {
          'authorization': 'Bearer $testApiKey',
          'content-length': '${15 * 1024 * 1024}', // 15MB
        },
      );
      final response = await handler(oversizedRequest);
      expect(response.statusCode, equals(413));
      final body = json.decode(await response.readAsString());
      expect(body['error']['type'], equals('payload_too_large'));
    });
  });
}

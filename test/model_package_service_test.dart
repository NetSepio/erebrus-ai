import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:erebrus_ai/data/catalog_entry.dart';
import 'package:erebrus_ai/services/model_package_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late HttpServer server;
  final payloads = <String, List<int>>{};
  String url(String path) =>
      'http://${server.address.host}:${server.port}$path';

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'erebrus-model-package-test-',
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final payload = payloads[request.uri.path];
      if (payload == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.contentLength = payload.length;
        request.response.add(payload);
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await temporaryDirectory.delete(recursive: true);
    payloads.clear();
  });

  test(
    'installs, verifies, indexes, and resolves a variant atomically',
    () async {
      final bytes = utf8.encode('tiny model fixture');
      payloads['/model.gguf'] = bytes;
      final variant = _variant(
        id: 'tiny-q8',
        bytes: bytes,
        url: url('/model.gguf'),
      );
      final service = ModelPackageService(
        modelsDirectoryProvider: () async => temporaryDirectory,
      );
      final progress = <int>[];

      final installed = await service.downloadVariant(
        variant,
        onProgress: (_, received, _) => progress.add(received),
      );

      expect(installed.runnable, isTrue);
      expect(installed.variantId, 'tiny-q8');
      expect(progress.last, bytes.length);
      expect(await service.packagePath(variant.id), endsWith('model.gguf'));
      expect(
        await Directory(
          temporaryDirectory.path,
        ).list().where((entry) => entry.path.endsWith('.part')).isEmpty,
        isTrue,
      );

      final restored = ModelPackageService(
        modelsDirectoryProvider: () async => temporaryDirectory,
      );
      await restored.loadIndex();
      expect(restored.byVariantId(variant.id)?.runnable, isTrue);
      expect(
        (await restored.verify(variant)).files.single.sha256,
        sha256.convert(bytes).toString(),
      );
    },
  );

  test('checksum failure never publishes a runnable package', () async {
    final bytes = utf8.encode('corrupt model fixture');
    payloads['/bad.gguf'] = bytes;
    final variant = _variant(
      id: 'bad-q8',
      bytes: bytes,
      url: url('/bad.gguf'),
      checksum: '0' * 64,
    );
    final service = ModelPackageService(
      modelsDirectoryProvider: () async => temporaryDirectory,
    );

    await expectLater(
      service.downloadVariant(variant),
      throwsA(
        isA<ModelPackageException>().having(
          (error) => error.code,
          'code',
          'checksum_mismatch',
        ),
      ),
    );

    expect(service.byVariantId(variant.id), isNull);
    expect(await service.packagePath(variant.id), isNull);
    expect(
      await Directory('${temporaryDirectory.path}/bad-q8').exists(),
      isFalse,
    );
  });
}

ModelVariant _variant({
  required String id,
  required List<int> bytes,
  required String url,
  String? checksum,
}) => ModelVariant(
  id: id,
  modelId: 'tiny',
  format: 'gguf',
  quantization: 'Q8_0',
  compatibleBackends: const ['llama.cpp'],
  files: [
    Artifact(
      id: '$id-model',
      role: 'model',
      format: 'gguf',
      quantization: 'Q8_0',
      filename: 'model.gguf',
      repositoryId: 'fixture',
      downloadUrl: url,
      sizeBytes: bytes.length,
      sha256: checksum ?? sha256.convert(bytes).toString(),
    ),
  ],
);

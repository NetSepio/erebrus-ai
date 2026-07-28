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
        if (request.uri.path == '/slow.gguf') {
          for (var offset = 0; offset < payload.length; offset += 8192) {
            final end = (offset + 8192).clamp(0, payload.length);
            request.response.add(payload.sublist(offset, end));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 3));
          }
        } else {
          request.response.add(payload);
        }
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

      final secondBytes = utf8.encode('second quantization fixture');
      payloads['/model-q4.gguf'] = secondBytes;
      final secondVariant = _variant(
        id: 'tiny-q4',
        bytes: secondBytes,
        url: url('/model-q4.gguf'),
      );
      await restored.downloadVariant(secondVariant);

      expect(restored.installed.map((record) => record.variantId), {
        'tiny-q8',
        'tiny-q4',
      });
      expect(await restored.packagePath('tiny-q8'), isNotNull);
      expect(await restored.packagePath('tiny-q4'), isNotNull);
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

  test('cancels an active package and removes staging files', () async {
    final bytes = List<int>.generate(1024 * 1024, (index) => index % 251);
    payloads['/slow.gguf'] = bytes;
    final variant = _variant(
      id: 'cancel-q8',
      bytes: bytes,
      url: url('/slow.gguf'),
    );
    final service = ModelPackageService(
      modelsDirectoryProvider: () async => temporaryDirectory,
    );

    final download = service.downloadVariant(variant);
    while (!service.isDownloading(variant.id)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await Future<void>.delayed(const Duration(milliseconds: 12));
    await service.cancelDownload(variant.id);

    await expectLater(
      download,
      throwsA(
        isA<ModelPackageException>().having(
          (error) => error.code,
          'code',
          'download_cancelled',
        ),
      ),
    );
    expect(service.isDownloading(variant.id), isFalse);
    expect(service.byVariantId(variant.id), isNull);
    expect(
      await temporaryDirectory
          .list()
          .where((entry) => entry.path.endsWith('.part'))
          .isEmpty,
      isTrue,
    );
  });

  test('detects a catalog revision, updates, and rolls back', () async {
    final firstBytes = utf8.encode('first model revision');
    final secondBytes = utf8.encode('second model revision');
    payloads['/first.gguf'] = firstBytes;
    payloads['/second.gguf'] = secondBytes;
    final first = _variant(
      id: 'rolling-q8',
      bytes: firstBytes,
      url: url('/first.gguf'),
    );
    final second = _variant(
      id: 'rolling-q8',
      bytes: secondBytes,
      url: url('/second.gguf'),
    );
    final service = ModelPackageService(
      modelsDirectoryProvider: () async => temporaryDirectory,
    );

    await service.downloadVariant(first);
    expect(service.hasUpdate(second), isTrue);
    await service.updateVariant(second);
    final activePath = await service.packagePath(second.id);
    expect(await File(activePath!).readAsBytes(), secondBytes);
    expect(service.canRollback(second.id), isTrue);

    expect(await service.rollback(second.id), isTrue);
    expect(await File(activePath).readAsBytes(), firstBytes);

    final restored = ModelPackageService(
      modelsDirectoryProvider: () async => temporaryDirectory,
    );
    await restored.loadIndex();
    expect(restored.canRollback(second.id), isTrue);
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

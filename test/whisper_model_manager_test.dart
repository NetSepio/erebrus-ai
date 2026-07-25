import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:erebrus_ai/services/whisper_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late HttpServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('erebrus-whisper-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('installs a revision-pinned Whisper model atomically', () async {
    final bytes = utf8.encode('whisper model fixture');
    server.listen((request) async {
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
    final spec = WhisperModelSpec(
      id: 'fixture',
      filename: 'ggml-fixture.bin',
      downloadUrl: 'http://${server.address.host}:${server.port}/model',
      revision: 'fixture-revision',
      sizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      minimumRamGB: 0.1,
    );
    final manager = WhisperModelManager(
      directoryProvider: () async => directory,
      spec: spec,
    );

    final path = await manager.install();

    expect(path, endsWith(spec.filename));
    expect(await manager.installedPath(), path);
    expect(manager.progress, 1);
    expect(File('$path.part').existsSync(), isFalse);
  });

  test('rejects a corrupt Whisper model without publishing it', () async {
    final bytes = utf8.encode('corrupt');
    server.listen((request) async {
      request.response.add(bytes);
      await request.response.close();
    });
    final manager = WhisperModelManager(
      directoryProvider: () async => directory,
      spec: WhisperModelSpec(
        id: 'fixture',
        filename: 'ggml-fixture.bin',
        downloadUrl: 'http://${server.address.host}:${server.port}/model',
        revision: 'fixture-revision',
        sizeBytes: bytes.length,
        sha256: '0' * 64,
        minimumRamGB: 0.1,
      ),
    );

    await expectLater(manager.install(), throwsStateError);

    expect(await manager.installedPath(), isNull);
    expect(
      await directory
          .list()
          .where((entry) => entry.path.endsWith('.part'))
          .isEmpty,
      isTrue,
    );
  });

  test(
    'keeps a verified previous revision and rolls back atomically',
    () async {
      final firstBytes = utf8.encode('first verified model');
      final secondBytes = utf8.encode('second verified model');
      server.listen((request) async {
        final bytes = request.uri.path.endsWith('second')
            ? secondBytes
            : firstBytes;
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      WhisperModelSpec fixture(
        String revision,
        String endpoint,
        List<int> bytes,
      ) => WhisperModelSpec(
        id: 'fixture',
        filename: 'ggml-fixture.bin',
        downloadUrl: 'http://${server.address.host}:${server.port}/$endpoint',
        revision: revision,
        sizeBytes: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        minimumRamGB: 0.1,
      );

      final first = WhisperModelManager(
        directoryProvider: () async => directory,
        spec: fixture('revision-1', 'first', firstBytes),
      );
      await first.install();
      final second = WhisperModelManager(
        directoryProvider: () async => directory,
        spec: fixture('revision-2', 'second', secondBytes),
      );
      final path = await second.install();

      expect(await File(path).readAsBytes(), secondBytes);
      expect(File('$path.previous').existsSync(), isTrue);
      expect(second.activeRevision, 'revision-2');
      expect(await second.rollback(), isTrue);
      expect(await File(path).readAsBytes(), firstBytes);
      expect(second.activeRevision, 'revision-1');
    },
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:erebrus_ai/services/speech_package_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late HttpServer server;
  final files = {
    'model.onnx': utf8.encode('speech model fixture'),
    'tokens.txt': utf8.encode('a 0\nb 1\n'),
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('erebrus-speech-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  SpeechPackageSpec spec({Map<String, String> digests = const {}}) =>
      SpeechPackageSpec(
        id: 'fixture-package',
        family: SpeechPackageFamily.moonshine,
        displayName: 'Fixture',
        summary: 'Fixture',
        license: 'MIT',
        minimumRamGB: 0.1,
        files: [
          for (final MapEntry(:key, :value) in files.entries)
            SpeechPackageFile(
              name: key,
              downloadUrl: 'http://${server.address.host}:${server.port}/$key',
              sizeBytes: value.length,
              sha256: digests[key] ?? sha256.convert(value).toString(),
            ),
        ],
      );

  void serve() => server.listen((request) async {
    final bytes = files[p.basename(request.uri.path)]!;
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  });

  test('installs every file and publishes the package atomically', () async {
    serve();
    final manager = SpeechPackageManager(
      spec: spec(),
      directoryProvider: () async => directory,
    );

    final path = await manager.install();

    expect(p.basename(path), 'fixture-package');
    expect(await manager.installedPath(), path);
    expect(manager.progress, 1);
    for (final name in files.keys) {
      expect(File(p.join(path, name)).readAsBytesSync(), files[name]);
    }
    expect(Directory('$path.part').existsSync(), isFalse);
  });

  test('rejects a corrupt file and publishes nothing', () async {
    serve();
    final manager = SpeechPackageManager(
      spec: spec(digests: {'tokens.txt': '0' * 64}),
      directoryProvider: () async => directory,
    );

    await expectLater(manager.install(), throwsStateError);

    expect(await manager.installedPath(), isNull);
    expect(directory.listSync(), isEmpty);
    expect(manager.failure, contains('tokens.txt'));
  });

  test('a tampered installed file is no longer reported installed', () async {
    serve();
    final installer = SpeechPackageManager(
      spec: spec(),
      directoryProvider: () async => directory,
    );
    final path = await installer.install();
    File(p.join(path, 'model.onnx')).writeAsStringSync('tampered!!!!!!!!!!!!');

    final fresh = SpeechPackageManager(
      spec: spec(),
      directoryProvider: () async => directory,
    );

    expect(await fresh.installedPath(), isNull);
  });

  test('delete removes the package', () async {
    serve();
    final manager = SpeechPackageManager(
      spec: spec(),
      directoryProvider: () async => directory,
    );
    final path = await manager.install();

    await manager.delete();

    expect(Directory(path).existsSync(), isFalse);
    expect(await manager.installedPath(), isNull);
  });

  test('pinned packages bundle Silero VAD and immutable revisions', () {
    for (final spec in SpeechPackageManager.specs) {
      expect(
        spec.files.map((file) => file.name),
        contains('silero_vad.onnx'),
        reason: spec.id,
      );
      for (final file in spec.files) {
        expect(file.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(file.sizeBytes, greaterThan(0));
        expect(
          file.downloadUrl,
          matches(RegExp(r'^https://huggingface\.co/.+/resolve/[0-9a-f]{40}/')),
        );
      }
    }
  });
}

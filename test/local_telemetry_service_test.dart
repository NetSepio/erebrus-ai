import 'dart:io';

import 'package:erebrus_ai/services/local_telemetry_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late LocalTelemetryService telemetry;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'erebrus-telemetry-test-',
    );
    telemetry = LocalTelemetryService(
      directoryProvider: () async => temporaryDirectory,
    );
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test('events stay local and round-trip as JSONL', () async {
    await telemetry.record(
      LocalTelemetryEvent(
        kind: LocalTelemetryEventKind.inference,
        recordedAt: DateTime.utc(2026, 7, 25),
        success: true,
        backend: 'mlx',
        modelVariantId: 'model-variant',
        durationMilliseconds: 400,
        metrics: const {'tokens_per_second': 42.5, 'fallback': false},
      ),
    );

    final events = await telemetry.readAll();

    expect(events, hasLength(1));
    expect(events.single.backend, 'mlx');
    expect(events.single.metrics['tokens_per_second'], 42.5);
  });

  test('export requires explicit consent', () async {
    final destination = File('${temporaryDirectory.path}/export/events.jsonl');

    expect(
      () => telemetry.exportTo(destination, userConsented: false),
      throwsStateError,
    );
    await telemetry.exportTo(destination, userConsented: true);
    expect(await destination.exists(), isTrue);
  });

  test('sensitive string metric values are rejected', () async {
    final event = LocalTelemetryEvent(
      kind: LocalTelemetryEventKind.transcription,
      recordedAt: DateTime.utc(2026, 7, 25),
      success: true,
      metrics: const {'transcript': 'private words'},
    );

    expect(() => telemetry.record(event), throwsArgumentError);
  });
}

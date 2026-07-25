import 'dart:convert';
import 'dart:io';

import 'storage_service.dart';

enum LocalTelemetryEventKind {
  backendProbe,
  modelLoad,
  inference,
  transcription,
  fallback,
}

class LocalTelemetryEvent {
  const LocalTelemetryEvent({
    required this.kind,
    required this.recordedAt,
    required this.success,
    this.backend = '',
    this.modelVariantId = '',
    this.durationMilliseconds,
    this.reasonCode = '',
    this.metrics = const {},
    this.schemaVersion = 1,
  });

  factory LocalTelemetryEvent.fromJson(Map<String, Object?> json) =>
      LocalTelemetryEvent(
        schemaVersion: json['schema_version'] as int? ?? 1,
        kind: LocalTelemetryEventKind.values.byName(json['kind'] as String),
        recordedAt: DateTime.parse(json['recorded_at'] as String).toUtc(),
        success: json['success'] == true,
        backend: json['backend'] as String? ?? '',
        modelVariantId: json['model_variant_id'] as String? ?? '',
        durationMilliseconds: json['duration_ms'] as int?,
        reasonCode: json['reason_code'] as String? ?? '',
        metrics: switch (json['metrics']) {
          final Map<Object?, Object?> value => value.cast<String, Object?>(),
          _ => const {},
        },
      );

  final int schemaVersion;
  final LocalTelemetryEventKind kind;
  final DateTime recordedAt;
  final bool success;
  final String backend;
  final String modelVariantId;
  final int? durationMilliseconds;
  final String reasonCode;

  /// Numeric/boolean operational measurements only. Prompts, generated text,
  /// transcripts, file paths, account IDs, and device identifiers are forbidden.
  final Map<String, Object?> metrics;

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'kind': kind.name,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'success': success,
    'backend': backend,
    'model_variant_id': modelVariantId,
    'duration_ms': durationMilliseconds,
    'reason_code': reasonCode,
    'metrics': metrics,
  };
}

class LocalTelemetryService {
  LocalTelemetryService({Future<Directory> Function()? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? StorageService.instance.telemetryDir;

  final Future<Directory> Function() _directoryProvider;

  Future<File> get _eventsFile async =>
      File('${(await _directoryProvider()).path}/events.jsonl');

  Future<void> record(LocalTelemetryEvent event) async {
    _validateMetrics(event.metrics);
    final file = await _eventsFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(event.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<List<LocalTelemetryEvent>> readAll() async {
    final file = await _eventsFile;
    if (!await file.exists()) return const [];
    final lines = await file.readAsLines();
    return lines
        .where((line) => line.trim().isNotEmpty)
        .map(
          (line) => LocalTelemetryEvent.fromJson(
            (jsonDecode(line) as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList(growable: false);
  }

  Future<File> exportTo(File destination, {required bool userConsented}) async {
    if (!userConsented) {
      throw StateError('Telemetry export requires explicit user consent.');
    }
    final source = await _eventsFile;
    if (!await source.exists()) {
      await destination.parent.create(recursive: true);
      return destination.writeAsString('', flush: true);
    }
    await destination.parent.create(recursive: true);
    return source.copy(destination.path);
  }

  static void _validateMetrics(Map<String, Object?> metrics) {
    for (final entry in metrics.entries) {
      final value = entry.value;
      if (value != null && value is! num && value is! bool) {
        throw ArgumentError.value(
          value,
          entry.key,
          'Telemetry metrics may contain only numbers, booleans, or null',
        );
      }
    }
  }
}

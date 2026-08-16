import 'dart:convert';

import 'backend_probe_service.dart';
import 'device_info_service.dart';
import 'imported_model_service.dart';
import 'model_package_service.dart';
import 'transcription_session_repository.dart';
import 'whisper_model_manager.dart';

/// Builds a shareable diagnostics report without filesystem paths, prompts,
/// transcripts, wallet data, or device identifiers.
class OnDeviceDiagnosticsService {
  const OnDeviceDiagnosticsService();

  Future<Map<String, Object?>> collect({
    required String defaultModelId,
    required String defaultVariantId,
  }) async {
    final profile = DeviceInfoService.detect();
    final backendService = BackendProbeService.instance;
    final capabilities = await backendService.probe(device: profile);
    final asrPath = await WhisperModelManager.instance.installedPath();
    final transcriptRepository = TranscriptionSessionRepository.instance;
    final model = defaultVariantId.isEmpty
        ? null
        : ModelPackageService.instance.byVariantId(defaultVariantId);
    final imported = ImportedModelService.instance.byId(defaultModelId);
    return {
      'schema_version': 1,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'device_class': profile.type.name,
      'platform': profile.platform,
      'ram_gb': double.parse(profile.ramGB.toStringAsFixed(1)),
      'inference': {
        'active': backendService.activeLabel,
        'capabilities': capabilities
            .map(
              (capability) => {
                'backend': capability.kind.catalogName,
                'operational': capability.operational,
                'accelerators': capability.accelerators,
                'formats': capability.formats,
                'reason': _redact(capability.reason),
              },
            )
            .toList(growable: false),
      },
      'default_model': {
        'model_id': defaultModelId,
        'variant_id': defaultVariantId,
        'installed': model?.runnable == true || imported != null,
        'format': model?.format ?? imported?.format ?? '',
        'backends':
            model?.backends ??
            (imported == null ? const <String>[] : [imported.backend]),
      },
      'transcription': {
        'preferred': 'SpeechAnalyzer when runtime probe succeeds',
        'fallback': 'whisper.cpp',
        'whisper_installed': asrPath != null,
        'whisper_revision': WhisperModelManager.instance.spec.revision,
        'session_count': transcriptRepository.sessions.length,
        'storage_bytes': await transcriptRepository.storageBytes(),
      },
      'privacy': {
        'contains_transcripts': false,
        'contains_prompts': false,
        'contains_filesystem_paths': false,
        'contains_credentials': false,
      },
    };
  }

  Future<String> collectJson({
    required String defaultModelId,
    required String defaultVariantId,
  }) async => const JsonEncoder.withIndent(' ').convert(
    await collect(
      defaultModelId: defaultModelId,
      defaultVariantId: defaultVariantId,
    ),
  );

  static String _redact(String value) => value
      .replaceAll(RegExp(r'(?<!\w)/(?:[^/\s]+/)+[^/\s]+'), '<redacted-path>')
      .replaceAll(
        RegExp(r'\b[A-Za-z]:\\(?:[^\\\s]+\\)+[^\\\s]+'),
        '<redacted-path>',
      );
}

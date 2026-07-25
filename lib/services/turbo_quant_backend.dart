import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:erebrus_turboquant/erebrus_turboquant.dart';
import 'package:uuid/uuid.dart';

import '../data/catalog_entry.dart';
import 'inference_contract.dart';

class TurboQuantRuntimeProbe {
  const TurboQuantRuntimeProbe({
    required this.operational,
    required this.accelerator,
    required this.reason,
  });

  final bool operational;
  final String accelerator;
  final String reason;
}

abstract interface class TurboQuantRuntime {
  Future<TurboQuantRuntimeProbe> probe();
  Future<void> start({
    required String modelPath,
    required int contextSize,
    required int gpuLayerCount,
  });
  Stream<InferenceEvent> generate(InferenceRequest request);
  Future<void> cancel();
  Future<void> stop();
}

class TurboQuantServerRuntime implements TurboQuantRuntime {
  TurboQuantServerRuntime([this._locator = const TurboQuantRuntimeLocator()]);

  final TurboQuantRuntimeLocator _locator;
  Process? _process;
  HttpClient? _activeClient;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final List<String> _startupLog = [];
  String _accelerator = 'CPU';
  String _apiKey = '';
  int _port = 0;
  int? _exitCode;

  @override
  Future<TurboQuantRuntimeProbe> probe() async {
    if (!Platform.isLinux && !Platform.isWindows) {
      return const TurboQuantRuntimeProbe(
        operational: false,
        accelerator: '',
        reason: 'TurboQuant desktop runtime supports Windows and Linux',
      );
    }
    final executable = await _locator.resolve();
    final manifest = await _locator.manifest();
    if (executable == null || manifest == null) {
      return const TurboQuantRuntimeProbe(
        operational: false,
        accelerator: '',
        reason: 'The packaged TurboQuant runtime or manifest is missing',
      );
    }
    if (manifest['revision'] != TurboQuantRuntimeProvenance.revision ||
        manifest['source_archive_sha256'] !=
            TurboQuantRuntimeProvenance.sourceArchiveSha256 ||
        manifest['key_cache'] != TurboQuantRuntimeProvenance.keyCache ||
        manifest['value_cache'] != TurboQuantRuntimeProvenance.valueCache) {
      return const TurboQuantRuntimeProbe(
        operational: false,
        accelerator: '',
        reason: 'The packaged TurboQuant provenance manifest is invalid',
      );
    }
    final accelerator = manifest['accelerator']?.toString().toUpperCase() ?? '';
    if (!const {'CPU', 'CUDA', 'HIP'}.contains(accelerator)) {
      return const TurboQuantRuntimeProbe(
        operational: false,
        accelerator: '',
        reason: 'The packaged TurboQuant accelerator is unsupported',
      );
    }
    _accelerator = accelerator;
    return TurboQuantRuntimeProbe(
      operational: true,
      accelerator: accelerator,
      reason:
          'Pinned TurboQuant+ '
          '${TurboQuantRuntimeProvenance.keyCache}/'
          '${TurboQuantRuntimeProvenance.valueCache} · '
          '${TurboQuantRuntimeProvenance.revision.substring(0, 7)} · '
          '$accelerator',
    );
  }

  @override
  Future<void> start({
    required String modelPath,
    required int contextSize,
    required int gpuLayerCount,
  }) async {
    await stop();
    final probeResult = await probe();
    if (!probeResult.operational) {
      throw StateError(probeResult.reason);
    }
    final executable = await _locator.resolve();
    if (executable == null) {
      throw StateError('The TurboQuant executable disappeared');
    }
    _apiKey = const Uuid().v4();
    _port = await _reserveLoopbackPort();
    _startupLog.clear();
    _exitCode = null;

    final process = await Process.start(executable.path, [
      '--model',
      modelPath,
      '--ctx-size',
      '$contextSize',
      '--cache-type-k',
      TurboQuantRuntimeProvenance.keyCache,
      '--cache-type-v',
      TurboQuantRuntimeProvenance.valueCache,
      '--flash-attn',
      'on',
      '--n-gpu-layers',
      '${_accelerator == 'CPU' ? 0 : gpuLayerCount}',
      '--host',
      InternetAddress.loopbackIPv4.address,
      '--port',
      '$_port',
      '--api-key',
      _apiKey,
      '--parallel',
      '1',
      '--no-webui',
      '--no-slots',
      '--cache-ram',
      '0',
    ], runInShell: false);
    _process = process;
    process.exitCode.then((value) => _exitCode = value);
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_rememberStartupLine);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_rememberStartupLine);

    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      final exitCode = _exitCode;
      if (exitCode != null) {
        final detail = _startupLog.isEmpty ? '' : ': ${_startupLog.last}';
        await stop();
        throw StateError(
          'TurboQuant runtime exited during model load ($exitCode)$detail',
        );
      }
      if (await _isHealthy()) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await stop();
    throw TimeoutException('TurboQuant model load timed out');
  }

  @override
  Stream<InferenceEvent> generate(InferenceRequest request) async* {
    if (_process == null || _port == 0) {
      yield const InferenceFailure(
        code: 'turboquant_not_loaded',
        message: 'Load the TurboQuant runtime before generation',
        retryable: true,
      );
      return;
    }
    final client = HttpClient();
    _activeClient = client;
    final clock = Stopwatch()..start();
    var emitted = false;
    var generatedTokens = 0;
    var completionReason = InferenceFinishReason.stop;
    try {
      final httpRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:$_port/v1/chat/completions'),
      );
      httpRequest.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey');
      httpRequest.write(
        jsonEncode({
          'messages': [
            for (final message in request.messages)
              {'role': message.role, 'content': message.content},
          ],
          'stream': true,
          'stream_options': {'include_usage': true},
          'max_tokens': request.maxOutputTokens,
          'temperature': request.sampling.temperature,
          'top_p': request.sampling.topP,
          'top_k': request.sampling.topK,
          'min_p': request.sampling.minP,
          'repeat_penalty': request.sampling.repeatPenalty,
          'seed': request.sampling.seed,
          if (request.stopSequences.isNotEmpty) 'stop': request.stopSequences,
          if (request.tools.isNotEmpty) 'tools': request.tools,
        }),
      );
      final response = await httpRequest.close();
      if (response.statusCode != HttpStatus.ok) {
        final body = await utf8.decoder.bind(response).join();
        yield InferenceFailure(
          code: 'turboquant_http_${response.statusCode}',
          message: _safeServerError(body),
          retryable: true,
        );
        return;
      }

      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        final decoded = jsonDecode(data);
        if (decoded is! Map) continue;
        final json = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final choices = json['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final choice = (choices.first as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          );
          final delta = choice['delta'];
          if (delta is Map) {
            final content = delta['content'];
            if (content is String && content.isNotEmpty) {
              generatedTokens++;
              if (!emitted) {
                emitted = true;
                yield InferenceMetrics(timeToFirstToken: clock.elapsed);
              }
              yield InferenceToken(content);
            }
          }
          final finishReason = choice['finish_reason'];
          if (finishReason != null) {
            completionReason = _finishReason(finishReason);
          }
        }
        final timings = json['timings'];
        if (timings is Map) {
          final predicted = timings['predicted_n'];
          final speed = timings['predicted_per_second'];
          if (predicted is num) generatedTokens = predicted.toInt();
          if (speed is num) {
            yield InferenceMetrics(decodeTokensPerSecond: speed.toDouble());
          }
        }
      }
      yield InferenceCompleted(
        reason: completionReason,
        generatedTokens: generatedTokens,
      );
    } on Object catch (error) {
      yield InferenceFailure(
        code: 'turboquant_generation_failed',
        message: error.toString(),
        retryable: !emitted,
        beforeFirstToken: !emitted,
      );
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close(force: true);
    }
  }

  @override
  Future<void> cancel() async {
    _activeClient?.close(force: true);
    _activeClient = null;
  }

  @override
  Future<void> stop() async {
    await cancel();
    final process = _process;
    _process = null;
    _port = 0;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        try {
          process.kill(ProcessSignal.sigkill);
        } on Object {
          process.kill();
        }
      }
    }
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
  }

  Future<bool> _isHealthy() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$_port/health'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey');
      final response = await request.close().timeout(
        const Duration(seconds: 1),
      );
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  void _rememberStartupLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    _startupLog.add(trimmed);
    if (_startupLog.length > 20) _startupLog.removeAt(0);
  }

  static Future<int> _reserveLoopbackPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static String _safeServerError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
      }
    } on FormatException {
      // Do not expose an HTML body or request echo in diagnostics.
    }
    return 'TurboQuant server rejected the request';
  }

  static InferenceFinishReason _finishReason(Object? value) => switch (value) {
    'length' => InferenceFinishReason.length,
    'cancelled' => InferenceFinishReason.cancelled,
    _ => InferenceFinishReason.stop,
  };
}

class TurboQuantBackend implements InferenceBackend {
  TurboQuantBackend({required this.platform, TurboQuantRuntime? runtime})
    : _runtime = runtime ?? TurboQuantServerRuntime();

  final String platform;
  final TurboQuantRuntime _runtime;
  String? _loadedVariantId;
  String? _loadedPackagePath;
  int? _loadedContextSize;
  int? _loadedGpuLayerCount;
  TurboQuantRuntimeProbe? _probeResult;

  @override
  BackendKind get kind => BackendKind.turboQuant;

  @override
  Future<BackendCapabilities> probe() async {
    final result = await _runtime.probe();
    _probeResult = result;
    return BackendCapabilities(
      kind: kind,
      operational: result.operational,
      platforms: [platform],
      formats: const ['gguf'],
      accelerators: [if (result.accelerator.isNotEmpty) result.accelerator],
      reason: result.reason,
    );
  }

  @override
  bool supports(ModelVariant variant) {
    final desktop =
        platform.startsWith('linux-') || platform.startsWith('windows-');
    return desktop &&
        variant.format.toLowerCase() == 'gguf' &&
        variant.supportsPlatform(platform);
  }

  @override
  Future<void> load(InferenceLoadRequest request) async {
    if (!supports(request.variant)) {
      throw InferenceBackendException(
        code: 'unsupported_variant',
        message: 'TurboQuant does not support ${request.variant.id}',
      );
    }
    final probeResult = _probeResult ?? await _runtime.probe();
    _probeResult = probeResult;
    if (!probeResult.operational) {
      throw InferenceBackendException(
        code: 'runtime_unavailable',
        message: probeResult.reason,
      );
    }
    final requestedGpuLayerCount =
        request.gpuLayerCount ??
        (probeResult.accelerator.toUpperCase() == 'CPU' ? 0 : 99);
    if (_loadedVariantId == request.variant.id &&
        _loadedPackagePath == request.packagePath &&
        _loadedContextSize == request.contextSize &&
        _loadedGpuLayerCount == requestedGpuLayerCount) {
      return;
    }
    await _runtime.start(
      modelPath: request.packagePath,
      contextSize: request.contextSize,
      gpuLayerCount: requestedGpuLayerCount,
    );
    _loadedVariantId = request.variant.id;
    _loadedPackagePath = request.packagePath;
    _loadedContextSize = request.contextSize;
    _loadedGpuLayerCount = requestedGpuLayerCount;
  }

  @override
  Stream<InferenceEvent> generate(InferenceRequest request) =>
      _runtime.generate(request);

  @override
  Future<void> cancel() => _runtime.cancel();

  @override
  Future<void> unload() async {
    await _runtime.stop();
    _loadedVariantId = null;
    _loadedPackagePath = null;
    _loadedContextSize = null;
    _loadedGpuLayerCount = null;
  }
}

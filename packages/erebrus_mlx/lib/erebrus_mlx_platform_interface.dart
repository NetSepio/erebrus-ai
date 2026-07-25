import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'erebrus_mlx.dart';
import 'erebrus_mlx_method_channel.dart';

abstract class ErebrusMlxPlatform extends PlatformInterface {
  ErebrusMlxPlatform() : super(token: _token);

  static final Object _token = Object();
  static ErebrusMlxPlatform _instance = MethodChannelErebrusMlx();

  static ErebrusMlxPlatform get instance => _instance;

  static set instance(ErebrusMlxPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<MlxProbeResult> probe();

  Future<void> loadModel(String modelDirectory);

  Stream<MlxGenerationEvent> generate({
    required String prompt,
    required String systemPrompt,
    required int maxTokens,
    required int maxKvSize,
    required double temperature,
    required double topP,
  });

  Future<void> cancel();

  Future<void> unload();
}

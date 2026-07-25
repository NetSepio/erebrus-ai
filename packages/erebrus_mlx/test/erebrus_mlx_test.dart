import 'package:erebrus_mlx/erebrus_mlx.dart';
import 'package:erebrus_mlx/erebrus_mlx_method_channel.dart';
import 'package:erebrus_mlx/erebrus_mlx_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockErebrusMlxPlatform
    with MockPlatformInterfaceMixin
    implements ErebrusMlxPlatform {
  @override
  Future<MlxProbeResult> probe() async => const MlxProbeResult(
    available: true,
    metalAvailable: true,
    platform: 'macos-arm64',
    minimumOperatingSystem: 'macOS 14',
  );

  @override
  Future<void> loadModel(String modelDirectory) async {}

  @override
  Stream<MlxGenerationEvent> generate({
    required List<Map<String, String>> messages,
    required int maxTokens,
    required int maxKvSize,
    required double temperature,
    required double topP,
    required int topK,
    required double minP,
    required double repeatPenalty,
    required int seed,
  }) => Stream.value(const MlxGenerationEvent(type: 'token', text: 'hello'));

  @override
  Future<void> cancel() async {}

  @override
  Future<void> unload() async {}
}

void main() {
  final initialPlatform = ErebrusMlxPlatform.instance;

  test('$MethodChannelErebrusMlx is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelErebrusMlx>());
  });

  test('delegates probe and generation to the platform', () async {
    final plugin = ErebrusMlx();
    ErebrusMlxPlatform.instance = MockErebrusMlxPlatform();

    expect((await plugin.probe()).available, isTrue);
    expect(
      await plugin
          .generate(
            messages: const [
              {'role': 'user', 'content': 'test'},
            ],
          )
          .single,
      isA<MlxGenerationEvent>()
          .having((event) => event.type, 'type', 'token')
          .having((event) => event.text, 'text', 'hello'),
    );
  });
}

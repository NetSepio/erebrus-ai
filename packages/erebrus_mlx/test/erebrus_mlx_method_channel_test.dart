import 'package:erebrus_mlx/erebrus_mlx_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelErebrusMlx();
  const channel = MethodChannel('erebrus_mlx/methods');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'probe') {
            return {
              'available': true,
              'metal_available': true,
              'platform': 'macos-arm64',
              'minimum_os': 'macOS 14',
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('probe parses native capability fields', () async {
    final result = await platform.probe();

    expect(result.available, isTrue);
    expect(result.metalAvailable, isTrue);
    expect(result.platform, 'macos-arm64');
  });
}

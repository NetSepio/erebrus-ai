import 'dart:io';

import 'package:erebrus_ai/services/power_service.dart';
import 'package:erebrus_ai/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('foreground task plugin is limited to supported mobile platforms', () {
    expect(PowerService.supportsForegroundTaskPlatform('android'), isTrue);
    expect(PowerService.supportsForegroundTaskPlatform('ios'), isFalse);
    expect(PowerService.supportsForegroundTaskPlatform('macos'), isFalse);
    expect(PowerService.supportsForegroundTaskPlatform('windows'), isFalse);
    expect(PowerService.supportsForegroundTaskPlatform('linux'), isFalse);
  });

  test(
    'desktop app-settings fallback completes without a plugin channel',
    () async {
      if (Platform.isAndroid || Platform.isIOS) return;

      expect(StorageService.supportsAppPermissionSettings, isFalse);
      await expectLater(StorageService.instance.openSettings(), completes);
    },
  );
}

import 'dart:io';

import 'package:erebrus_ai/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy Android storage permission is only needed through API 28', () {
    expect(requiresLegacyAndroidStoragePermission(28), isTrue);
    expect(requiresLegacyAndroidStoragePermission(29), isFalse);
    expect(requiresLegacyAndroidStoragePermission(33), isFalse);
    expect(requiresLegacyAndroidStoragePermission(36), isFalse);
  });

  test('Android manifest limits legacy storage permissions to API 28', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      RegExp(
        r'READ_EXTERNAL_STORAGE"\s+android:maxSdkVersion="28"',
      ).hasMatch(manifest),
      isTrue,
    );
    expect(
      RegExp(
        r'WRITE_EXTERNAL_STORAGE"\s+android:maxSdkVersion="28"',
      ).hasMatch(manifest),
      isTrue,
    );
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
  });
}

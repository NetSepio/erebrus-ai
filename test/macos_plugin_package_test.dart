import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('checked-in macOS plugin aggregate matches Flutter dependencies', () {
    if (!Platform.isMacOS) return;

    final generated = File(
      'macos/Flutter/ephemeral/Packages/'
      'FlutterGeneratedPluginSwiftPackage/Package.swift',
    );
    final checkedIn = File('macos/Flutter/PluginSwiftPackage/Package.swift');

    expect(
      generated.existsSync(),
      isTrue,
      reason: 'Run flutter pub get before testing.',
    );

    Set<String> declarations(File file, String prefix) =>
        RegExp('${RegExp.escape(prefix)}\\(name: "([^"]+)"')
            .allMatches(file.readAsStringSync())
            .map((match) => match.group(1)!)
            .toSet();

    expect(
      declarations(checkedIn, '.package'),
      declarations(generated, '.package'),
      reason:
          'Flutter plugin dependencies changed. Refresh '
          'macos/Flutter/PluginSwiftPackage/Package.swift while preserving '
          'its macOS 14.0 platform and stable relative paths.',
    );
    expect(
      declarations(checkedIn, '.product'),
      declarations(generated, '.product'),
    );
  });
}

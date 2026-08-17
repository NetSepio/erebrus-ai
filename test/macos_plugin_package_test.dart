import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('checked-in macOS plugin aggregate matches Flutter dependencies', () {
    if (!Platform.isMacOS) return;

    _expectAggregateMatches('macos');
  });

  test('checked-in iOS plugin aggregate matches Flutter dependencies', () {
    if (!Platform.isMacOS) return;

    _expectAggregateMatches('ios');
  });
}

void _expectAggregateMatches(String platform) {
  final generated = File(
    '$platform/Flutter/ephemeral/Packages/'
    'FlutterGeneratedPluginSwiftPackage/Package.swift',
  );
  final checkedIn = File('$platform/Flutter/PluginSwiftPackage/Package.swift');

  expect(
    generated.existsSync(),
    isTrue,
    reason: 'Run flutter pub get before testing.',
  );

  Set<String> declarations(File file, String prefix) => RegExp(
    '${RegExp.escape(prefix)}\\(name: "([^"]+)"',
  ).allMatches(file.readAsStringSync()).map((match) => match.group(1)!).toSet();

  expect(
    declarations(checkedIn, '.package'),
    declarations(generated, '.package'),
    reason:
        'Flutter plugin dependencies changed. Refresh '
        '$platform/Flutter/PluginSwiftPackage/Package.swift while preserving '
        'its app deployment target and stable relative paths.',
  );
  expect(
    declarations(checkedIn, '.product'),
    declarations(generated, '.product'),
  );
}

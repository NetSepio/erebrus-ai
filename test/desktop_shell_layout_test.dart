import 'package:erebrus_ai/screens/shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shell keeps bottom navigation on phone-sized windows', () {
    expect(shellNavigationModeForWidth(719), ShellNavigationMode.bottom);
  });

  test('shell uses a compact left rail on medium desktop windows', () {
    expect(shellNavigationModeForWidth(720), ShellNavigationMode.compactRail);
    expect(shellNavigationModeForWidth(1024), ShellNavigationMode.compactRail);
    expect(shellNavigationModeForWidth(1199), ShellNavigationMode.compactRail);
  });

  test('shell expands the sidebar only on roomy desktop windows', () {
    expect(
      shellNavigationModeForWidth(1200),
      ShellNavigationMode.expandedSidebar,
    );
  });
}

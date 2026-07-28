import 'package:erebrus_ai/navigation/shell_tab.dart';
import 'package:erebrus_ai/screens/shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leaving Chat releases its resident inference model', () {
    for (final destination in ShellTab.values.where(
      (tab) => tab != ShellTab.chat,
    )) {
      expect(
        shouldReleaseChatModel(from: ShellTab.chat, to: destination),
        isTrue,
      );
    }
  });

  test('non-Chat navigation does not release a model owned by Chat', () {
    expect(
      shouldReleaseChatModel(from: ShellTab.transcribe, to: ShellTab.models),
      isFalse,
    );
    expect(
      shouldReleaseChatModel(from: ShellTab.chat, to: ShellTab.chat),
      isFalse,
    );
  });
}

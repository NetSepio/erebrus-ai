import 'package:erebrus_ai/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes complete leading think blocks', () {
    expect(
      sanitizeAssistantText('<think>private reasoning</think>\n\nVisible answer'),
      'Visible answer',
    );
  });

  test('hides an incomplete streaming think block', () {
    expect(sanitizeAssistantText('<think>still reasoning'), isEmpty);
  });

  test('keeps ordinary assistant text unchanged', () {
    expect(sanitizeAssistantText('A normal response'), 'A normal response');
  });
}

import 'package:erebrus_ai/services/transcript_prompt_template_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('custom transcript prompts remain explicit and local', () async {
    final service = TranscriptPromptTemplateService();
    await service.load();
    final template = await service.add(
      name: 'Risks',
      instruction: 'List only risks supported by the transcript.',
    );

    expect(service.templates, contains(template));
    expect(
      template.promptFor('private words'),
      contains('--- TRANSCRIPT ---\nprivate words'),
    );

    await service.delete(template.id);
    expect(
      service.templates.any((candidate) => candidate.id == template.id),
      isFalse,
    );
  });
}

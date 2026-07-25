import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class TranscriptPromptTemplate {
  const TranscriptPromptTemplate({
    required this.id,
    required this.name,
    required this.instruction,
    this.builtIn = false,
  });

  factory TranscriptPromptTemplate.fromJson(Map<String, Object?> json) =>
      TranscriptPromptTemplate(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        instruction: json['instruction'] as String? ?? '',
      );

  final String id;
  final String name;
  final String instruction;
  final bool builtIn;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'instruction': instruction,
  };

  String promptFor(String transcript) =>
      '$instruction\n\n--- TRANSCRIPT ---\n$transcript';
}

class TranscriptPromptTemplateService extends ChangeNotifier {
  static final TranscriptPromptTemplateService instance =
      TranscriptPromptTemplateService();

  static const _storageKey = 'transcript_prompt_templates_v1';
  static const builtIns = [
    TranscriptPromptTemplate(
      id: 'summary',
      name: 'Key points',
      instruction:
          'Summarize the key points in this transcript. Clearly separate facts, decisions, and uncertainties.',
      builtIn: true,
    ),
    TranscriptPromptTemplate(
      id: 'actions',
      name: 'Action items',
      instruction:
          'Extract action items from this transcript. Include an owner and due date only when the transcript states one.',
      builtIn: true,
    ),
    TranscriptPromptTemplate(
      id: 'questions',
      name: 'Ask about it',
      instruction:
          'Use this transcript as source material. Answer the question I add above this instruction, and identify any missing evidence.',
      builtIn: true,
    ),
  ];

  final List<TranscriptPromptTemplate> _custom = [];
  bool _loaded = false;

  List<TranscriptPromptTemplate> get templates =>
      List.unmodifiable([...builtIns, ..._custom]);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    try {
      final values = jsonDecode(prefs.getString(_storageKey) ?? '[]') as List;
      _custom
        ..clear()
        ..addAll(
          values.map(
            (value) => TranscriptPromptTemplate.fromJson(
              (value as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          ),
        );
    } on Object {
      _custom.clear();
    }
    notifyListeners();
  }

  Future<TranscriptPromptTemplate> add({
    required String name,
    required String instruction,
  }) async {
    final cleanName = name.trim();
    final cleanInstruction = instruction.trim();
    if (cleanName.isEmpty || cleanInstruction.isEmpty) {
      throw ArgumentError('Template name and instruction are required');
    }
    final template = TranscriptPromptTemplate(
      id: const Uuid().v4(),
      name: cleanName,
      instruction: cleanInstruction,
    );
    _custom.add(template);
    await _save();
    notifyListeners();
    return template;
  }

  Future<void> delete(String id) async {
    _custom.removeWhere((template) => template.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_custom.map((template) => template.toJson()).toList()),
    );
  }
}

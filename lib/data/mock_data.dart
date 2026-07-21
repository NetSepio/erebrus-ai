import 'package:flutter/widgets.dart';

/// Lightweight immutable view models shared by the model and persona screens.

enum ModelStatus { loaded, idle, downloading, catalog }

class MockModel {
  const MockModel(
    this.name,
    this.letter,
    this.spec, {
    this.id,
    this.status = ModelStatus.idle,
    this.progress,
    this.progressLabel,
    this.accent = false,
  });

  final String name;
  final String letter;

  /// Catalog id, when this model is backed by a downloadable catalog entry.
  final String? id;

  /// e.g. `Q4_K_M · 620 MB`
  final String spec;
  final ModelStatus status;
  final double? progress;
  final String? progressLabel;

  /// Accent-tinted letter avatar (the model currently in use).
  final bool accent;

  MockModel copyWith({
    String? name,
    String? letter,
    String? id,
    String? spec,
    ModelStatus? status,
    double? progress,
    String? progressLabel,
    bool? accent,
  }) {
    return MockModel(
      name ?? this.name,
      letter ?? this.letter,
      spec ?? this.spec,
      id: id ?? this.id,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      progressLabel: progressLabel ?? this.progressLabel,
      accent: accent ?? this.accent,
    );
  }
}

class MockNode {
  const MockNode(this.name, this.meta, this.icon, this.models);
  final String name;
  final String meta;
  final IconData icon;
  final List<MockModel> models;
}

// ─── Personas ────────────────────────────────────────────────────────────────

class MockPersona {
  const MockPersona(
    this.name,
    this.initials,
    this.meta, {
    this.id,
    required this.builtIn,
    this.systemPrompt = '',
    this.stopSequences = '',
    this.temperature = 0.7,
    this.topP = 0.9,
    this.maxTokens = 2048,
    this.repeatPenalty = 1.1,
  });

  final String? id;
  final String name;
  final String initials;
  final String meta;
  final bool builtIn;
  final String systemPrompt;
  final String stopSequences;
  final double temperature;
  final double topP;
  final int maxTokens;
  final double repeatPenalty;

  String get effectiveId => id ?? name;

  factory MockPersona.fromJson(Map<String, dynamic> json) => MockPersona(
    json['name'] as String,
    json['initials'] as String? ?? '',
    json['meta'] as String? ?? '',
    id: json['id'] as String?,
    builtIn: json['built_in'] as bool? ?? false,
    systemPrompt: json['system_prompt'] as String? ?? '',
    stopSequences: json['stop_sequences'] as String? ?? '',
    temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
    topP: (json['top_p'] as num?)?.toDouble() ?? 0.9,
    maxTokens: (json['max_tokens'] as int?) ?? 2048,
    repeatPenalty: (json['repeat_penalty'] as num?)?.toDouble() ?? 1.1,
  );

  Map<String, dynamic> toJson() => {
    'id': effectiveId,
    'name': name,
    'initials': initials,
    'meta': meta,
    'built_in': builtIn,
    'system_prompt': systemPrompt,
    'stop_sequences': stopSequences,
    'temperature': temperature,
    'top_p': topP,
    'max_tokens': maxTokens,
    'repeat_penalty': repeatPenalty,
  };

  MockPersona copyWith({
    String? id,
    String? name,
    String? initials,
    String? meta,
    bool? builtIn,
    String? systemPrompt,
    String? stopSequences,
    double? temperature,
    double? topP,
    int? maxTokens,
    double? repeatPenalty,
  }) => MockPersona(
    name ?? this.name,
    initials ?? this.initials,
    meta ?? this.meta,
    id: id ?? this.id,
    builtIn: builtIn ?? this.builtIn,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    stopSequences: stopSequences ?? this.stopSequences,
    temperature: temperature ?? this.temperature,
    topP: topP ?? this.topP,
    maxTokens: maxTokens ?? this.maxTokens,
    repeatPenalty: repeatPenalty ?? this.repeatPenalty,
  );
}

const mockBuiltInPersonas = [
  MockPersona(
    'Default',
    'DF',
    'TEMP 0.7 · 768 MAX',
    id: 'default',
    builtIn: true,
    maxTokens: 768,
  ),
  MockPersona(
    'Concise Analyst',
    'CA',
    'TEMP 0.4 · 512 MAX',
    id: 'concise-analyst',
    builtIn: true,
    systemPrompt:
        'You are a concise analyst. Answer in tight, information-dense prose. '
        'Lead with the conclusion, then give at most three supporting points. '
        'No filler, no hedging, and no bullet lists unless the user asks for them.',
    temperature: 0.4,
    maxTokens: 512,
  ),
  MockPersona(
    'Code Reviewer',
    'CR',
    'TEMP 0.2 · 1024 MAX',
    id: 'code-reviewer',
    builtIn: true,
    systemPrompt:
        'You are a rigorous code reviewer. Point out correctness issues first, '
        'style second. Cite the exact line you are commenting on.',
    temperature: 0.2,
    maxTokens: 1024,
  ),
  MockPersona(
    'Socratic Tutor',
    'ST',
    'TEMP 0.8 · 512 MAX',
    id: 'socratic-tutor',
    builtIn: true,
    systemPrompt:
        'You are a Socratic tutor. Never state the answer outright — guide '
        'the student with one probing question at a time.',
    temperature: 0.8,
    maxTokens: 512,
  ),
  MockPersona(
    'Research Synthesist',
    'RS',
    'TEMP 0.3 · 1024 MAX',
    id: 'research-synthesist',
    builtIn: true,
    systemPrompt:
        'You are a research synthesist. Separate verified facts, reasonable '
        'inferences, and uncertainty. Start with a direct answer, organize '
        'supporting evidence clearly, and never invent citations or sources.',
    temperature: 0.3,
    topP: 0.85,
    maxTokens: 1024,
    repeatPenalty: 1.08,
  ),
];

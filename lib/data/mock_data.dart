import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Static placeholder content for the screens-only pass. Everything here is
/// replaced by real stores/services (llama.cpp, mDNS, org API) in the next pass.

// ─── Chat ────────────────────────────────────────────────────────────────────

class MockSession {
  const MockSession(this.title, this.meta, {this.active = false});
  final String title;
  final String meta;
  final bool active;
}

const mockSessions = [
  MockSession('mDNS discovery notes', 'QWEN 3.5 · NOW', active: true),
  MockSession('Support tone rewrite', 'GEMMA 3 · 2H AGO'),
  MockSession('Quantization tradeoffs', 'QWEN 3.5 · YESTERDAY'),
  MockSession('Roadmap standup summary', 'MACBOOK-PRO · MON'),
  MockSession('Onboarding copy draft', 'LLAMA 3.2 · MON'),
];

class MockMessage {
  const MockMessage.user(this.text)
      : isUser = true,
        streaming = false,
        meta = null;
  const MockMessage.assistant(this.text, {this.meta})
      : isUser = false,
        streaming = false;
  const MockMessage.streaming(this.text)
      : isUser = false,
        streaming = true,
        meta = null;

  final bool isUser;

  /// Assistant text may contain `code` spans delimited by backticks.
  final String text;
  final bool streaming;
  final String? meta;
}

const mockMessages = [
  MockMessage.user(
      'Summarize what mDNS discovery means for our LAN setup — two sentences.'),
  MockMessage.assistant(
    'mDNS lets every device on your network announce and find services without '
    'a central server — this desktop broadcasts `_erebrus-ai._tcp`, and any '
    'phone on the Wi-Fi lists its models instantly. In practice: no IP '
    'addresses to type, no config — open the app and the node is just there.',
    meta: '0.9S · 214 TOKENS',
  ),
  MockMessage.user('And if the network blocks multicast?'),
  MockMessage.streaming(
    'Then discovery falls back to manual pairing — enter the node’s address '
    'and API key once, or scan its QR code from Settings. The connection itself '
    'is plain HTTP on your LAN, so once paired everything works the same',
  ),
];

// ─── Models ──────────────────────────────────────────────────────────────────

enum ModelStatus { loaded, idle, downloading, catalog }

class MockModel {
  const MockModel(
    this.name,
    this.letter,
    this.spec, {
    this.status = ModelStatus.idle,
    this.progress,
    this.progressLabel,
    this.accent = false,
  });

  final String name;
  final String letter;

  /// e.g. `Q4_K_M · 620 MB`
  final String spec;
  final ModelStatus status;
  final double? progress;
  final String? progressLabel;

  /// Accent-tinted letter avatar (the model currently in use).
  final bool accent;
}

const mockLocalModels = [
  MockModel('Qwen 3.5 0.8B', 'Q', 'Q4_K_M · 620 MB',
      status: ModelStatus.loaded, accent: true),
  MockModel('Llama 3.2 1B', 'L', 'Q8_0 · 1.3 GB',
      status: ModelStatus.downloading,
      progress: 0.72,
      progressLabel: '940 MB / 1.3 GB'),
  MockModel('Gemma 3 4B', 'G', 'Q4_K_M · 2.6 GB'),
];

const mockCatalogModels = [
  MockModel('DeepSeek R1 Distill 8B', 'D', 'Q5_K_M · 5.7 GB',
      status: ModelStatus.catalog),
  MockModel('Phi-4 Mini 3.8B', 'P', 'Q4_K_M · 2.4 GB',
      status: ModelStatus.catalog),
];

class MockNode {
  const MockNode(this.name, this.meta, this.icon, this.models);
  final String name;
  final String meta;
  final IconData icon;
  final List<MockModel> models;
}

const mockNodes = [
  MockNode(
    'Erebrus AI on MacBook-Pro',
    '192.168.1.24:11434 · MDNS · V1 · METAL',
    Symbols.laptop_mac,
    [
      MockModel('Qwen 3.5 14B', 'Q', 'Q4_K_M · 8.2 GB'),
      MockModel('Gemma 3 27B', 'G', 'Q4_K_M · 16.4 GB'),
      MockModel('DeepSeek R1 Distill 8B', 'D', 'Q5_K_M · 5.7 GB'),
    ],
  ),
  MockNode(
    'Erebrus AI on Pixel 9',
    '192.168.1.31:11434 · MDNS · V1 · IN-APP SERVER',
    Symbols.smartphone,
    [
      MockModel('Llama 3.2 1B', 'L', 'Q8_0 · 1.3 GB'),
    ],
  ),
];

const mockOrgNode = MockNode(
  'NetSepio Workspace',
  'erebrus-core-01 · 10.8.0.12:11434 · SHARED BY ADMIN@NETSEPIO.COM',
  Symbols.apartment,
  [
    MockModel('Sec-Analyst 8B', 'S', 'Q5_K_M · 5.6 GB · FINE-TUNED'),
    MockModel('Bonsai 27B Legal', 'B', 'Q4_K_M · 16.1 GB'),
  ],
);

// ─── Personas ────────────────────────────────────────────────────────────────

class MockPersona {
  const MockPersona(
    this.name,
    this.initials,
    this.meta, {
    required this.builtIn,
    this.systemPrompt = '',
    this.stopSequences = '',
    this.temperature = 0.7,
    this.topP = 0.9,
    this.maxTokens = 2048,
    this.repeatPenalty = 1.1,
  });

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
}

const mockBuiltInPersonas = [
  MockPersona('Default', 'DF', 'TEMP 0.7 · NO SYSTEM PROMPT', builtIn: true),
  MockPersona(
    'Concise Analyst',
    'CA',
    'TEMP 0.4 · 1024 MAX',
    builtIn: true,
    systemPrompt:
        'You are a concise analyst. Answer in tight, information-dense prose. '
        'Lead with the conclusion, then give at most three supporting points. '
        'No filler, no hedging, and no bullet lists unless the user asks for them.',
    stopSequences: '</answer>',
    temperature: 0.4,
    maxTokens: 1024,
  ),
  MockPersona('Code Reviewer', 'CR', 'TEMP 0.2 · STOP ```',
      builtIn: true,
      systemPrompt:
          'You are a rigorous code reviewer. Point out correctness issues first, '
          'style second. Cite the exact line you are commenting on.',
      stopSequences: '```',
      temperature: 0.2),
  MockPersona('Socratic Tutor', 'ST', 'TEMP 0.8 · QUESTIONS ONLY',
      builtIn: true,
      systemPrompt:
          'You are a Socratic tutor. Never state the answer outright — guide '
          'the student with one probing question at a time.',
      temperature: 0.8),
];

const mockYourPersonas = [
  MockPersona('Support Agent', 'SA', 'TEMP 0.5 · TEMPLATE',
      builtIn: false,
      systemPrompt:
          'You are the Erebrus support agent. Be warm, brief, and concrete. '
          'Always end with the single next step the user should take.',
      temperature: 0.5),
];

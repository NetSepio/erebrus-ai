# Offline transcription architecture

Erebrus records and transcribes locally. It never invokes an LLM during
transcription. **Analyze** is a separate, explicit action that opens an editable
Chat draft and uses the selected default local model only after the user sends
it.

## Backend policy

| Device | Preferred backend | Offline fallback |
| --- | --- | --- |
| iOS/macOS 26+ with a supported locale asset | Apple SpeechAnalyzer | whisper.cpp |
| Older supported iOS/macOS | whisper.cpp | none |
| Android | whisper.cpp | none |
| Windows/Linux | whisper.cpp | none |

SpeechAnalyzer provides live interim/final text. The whisper.cpp bridge is
file-based: Erebrus records a 16 kHz, mono PCM WAV, saves it first, then
transcribes it after Stop. This protects the original recording even if ASR
finalization fails. On constrained devices the loaded chat model is unloaded
before recording or ASR.

The initial ASR recommendation is the multilingual Whisper Tiny model for every
fallback device. Its roughly 74 MiB weight and 0.5 GB declared minimum-memory
tier prioritize reach on low-end phones. Larger ASR models are intentionally not
shown until device/language quality measurements justify their storage and
memory cost.

## Runtime and model provenance

- Flutter wrapper: `whisper_ggml_plus` **1.5.2**, exact-pinned in
  `pubspec.yaml`; it embeds whisper.cpp **1.8.3**.
- Upstream wrapper:
  <https://github.com/DDULDDUCK/whisper_ggml_plus>
- Model repository: <https://huggingface.co/ggerganov/whisper.cpp>
- Model: `ggml-tiny.bin`
- Immutable repository revision:
  `5359861c739e955e79d9a303bcbc70fb988958b1`
- Exact size: `77,691,713` bytes
- SHA-256:
  `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21`

The manager downloads to `.part`, validates exact size and SHA-256, and only
then atomically publishes the file. A verified prior revision remains in a
rollback slot. A package lock alone is not treated as model integrity. Asset
metadata is checked automatically after an app update, while the large download
remains an explicit user action to protect metered data, battery, and storage.

`whisper_ggml_plus` 1.5.2 has a universal-macOS pod definition defect: it
includes ARM GGML sources for the Intel slice and excludes the x86 sources.
`macos/Podfile` corrects the source set per architecture during pod generation.
Remove that patch only after the pinned upstream release contains and passes an
equivalent universal build fix.

## Session evidence

Each completed session contains:

```text
transcriptions/<session-id>/
  session.json
  audio.caf | audio.wav
  transcript.raw.json
  transcript.txt
  transcript.edited.txt  # only after an edit
```

`session.json` records backend/version, locale, duration, timestamps, audio
format, known sample rate/channel count, size, and SHA-256. The raw transcript
remains separate from user edits. Deleting only the transcript retains an
audio-only session that can still be replayed or shared.

The app maintains an atomic local search index over raw and edited transcript
text. Audio paths and metadata are excluded. Settings exposes storage size,
explicit full export (including audio), delete-all, and redacted backend/model/
ASR diagnostics. Optional analysis opens an editable Chat draft from a built-in
or user-authored local prompt template; recording and transcription never
invoke the LLM automatically.

## Verified build scope

On 26 July 2026:

- all 44 Flutter tests and static analysis passed;
- Android release APK built at 86.6 MB and contained Whisper libraries for
  `arm64-v8a`, `armeabi-v7a`, and `x86_64`;
- universal macOS release built at 171.1 MB and its Whisper framework contained
  `arm64` and `x86_64`;
- unsigned iOS device release built at 93.6 MB.

Windows and Linux native packaging are enforced by CI because Flutter cannot
cross-compile those desktop targets from macOS. Build success is not runtime
certification. Physical-device microphone, long-session, interruption,
low-storage, quality, thermal, and memory testing remain release gates.

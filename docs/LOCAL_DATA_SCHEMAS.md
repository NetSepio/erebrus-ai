# Local model, transcription, and telemetry schemas

All paths below are relative to the app-managed `ErebrusAI` directory. Absolute
paths are runtime details and must not be written to exported diagnostics.

## Model packages

The catalog schema separates a logical model from runnable `ModelVariant`
packages. A variant has a stable `variant_id`, `model_id`, format,
quantization, compatible backends, platform and memory constraints, release
channel, runtime floor, and one or more artifact records. Every artifact has a
stable ID, role, filename, revision, byte size, and SHA-256 digest.

Schema 1.0 flat GGUF records are projected into a synthetic llama.cpp variant
whose variant ID matches the legacy model ID. Schema 1.1 can publish GGUF and
complete MLX package variants side by side without presenting MLX weights as a
GGUF download.

The Phase 1 installed index will key files and state by `variant_id`, never only
by logical model ID:

```text
models/
  <variant-id>/
    manifest.json
    <required artifacts>
```

## Transcription sessions

The executable schema is `TranscriptionSession` in
`lib/data/transcription_session.dart`.

```text
transcriptions/
  <session-id>/
    session.json
    audio.caf or audio.m4a
```

`session.json` contains schema/session IDs, UTC timestamps, status, duration,
ASR backend/version, locale and asset version, relative audio metadata and
checksum, immutable raw text, optional edited text, final time-aligned
segments, explicit analysis chat IDs, and a typed failure code. Analysis always
uses edited text when it exists and otherwise uses raw text.

Audio paths are relative so a session can be moved, exported, restored, and
migrated. Interim text is intentionally not persisted as final evidence.

## Local telemetry

Operational events are appended to `telemetry/events.jsonl`. Recording is local
and has no network exporter. The only export API requires an explicit
`userConsented: true` argument and writes to a user-selected destination.

The schema permits backend and variant IDs, timestamps, success state, typed
reason codes, durations, and numeric/boolean metrics. It rejects string metric
values so prompts, generated text, transcripts, file paths, account IDs, and
device identifiers cannot accidentally enter the metrics map.

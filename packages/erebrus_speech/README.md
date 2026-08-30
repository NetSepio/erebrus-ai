# Erebrus Speech

Private Flutter plugin for Apple's on-device `SpeechAnalyzer` API. The plugin is
compiled into iOS and macOS builds (available on macOS 26 / iOS 26+).

The bridge probes locale/assets, captures microphone buffers, persists
the original session audio as CAF, streams `SpeechTranscriber` results in real-time,
and returns structured transcript segments with timecodes. Cross-platform fallback
for non-Apple devices is provided via the `whisper.cpp` engine.


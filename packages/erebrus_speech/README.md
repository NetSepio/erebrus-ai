# Erebrus Speech

Private Flutter plugin for Apple's on-device SpeechAnalyzer API. The plugin is
compiled into iOS and macOS builds but reports unavailable below OS 26.

The Phase 0 bridge can probe locale/assets, capture microphone buffers, persist
the original session audio as CAF, stream SpeechTranscriber results, and stop
with a transcript/audio result. Product UI and durable session storage are
implemented in later phases.

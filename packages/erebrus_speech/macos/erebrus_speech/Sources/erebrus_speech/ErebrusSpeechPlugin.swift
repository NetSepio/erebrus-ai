import AVFoundation
import Cocoa
@preconcurrency import FlutterMacOS
import Speech

public final class ErebrusSpeechPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
  @unchecked Sendable
{
  private var eventSink: FlutterEventSink?
  private var activeSession: Any?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ErebrusSpeechPlugin()
    let methods = FlutterMethodChannel(
      name: "erebrus_speech/methods",
      binaryMessenger: registrar.messenger
    )
    let events = FlutterEventChannel(
      name: "erebrus_speech/events",
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(instance, channel: methods)
    events.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "probe":
      let locale = arguments["locale"] as? String ?? ""
      Task {
        let payload = await probe(localeIdentifier: locale)
        complete(result, with: payload)
      }
    case "start":
      guard activeSession == nil else {
        result(FlutterError(code: "session_active", message: "A transcription session is already active", details: nil))
        return
      }
      guard
        let directory = arguments["session_directory"] as? String,
        !directory.isEmpty
      else {
        result(FlutterError(code: "invalid_arguments", message: "Missing session directory", details: nil))
        return
      }
      let locale = arguments["locale"] as? String ?? ""
      Task {
        do {
          guard await requestPermissions() else {
            throw SpeechBridgeError.permissionDenied
          }
          guard #available(macOS 26.0, *) else {
            throw SpeechBridgeError.unsupportedOperatingSystem
          }
          let session = try await SpeechAnalyzerCaptureSession.create(
            directory: URL(fileURLWithPath: directory, isDirectory: true),
            localeIdentifier: locale,
            emit: emit
          )
          try session.start()
          activeSession = session
          complete(result, with: session.audioURL.path)
        } catch {
          fail(result, code: "session_start_failed", error: error)
        }
      }
    case "stop":
      guard #available(macOS 26.0, *),
        let session = activeSession as? SpeechAnalyzerCaptureSession
      else {
        result(FlutterError(code: "no_active_session", message: "No transcription session is active", details: nil))
        return
      }
      Task {
        do {
          let payload = try await session.stop()
          activeSession = nil
          complete(result, with: payload)
        } catch {
          activeSession = nil
          fail(result, code: "session_stop_failed", error: error)
        }
      }
    case "pause":
      guard #available(macOS 26.0, *),
        let session = activeSession as? SpeechAnalyzerCaptureSession
      else {
        result(FlutterError(code: "no_active_session", message: "No transcription session is active", details: nil))
        return
      }
      session.pause()
      result(nil)
    case "resume":
      guard #available(macOS 26.0, *),
        let session = activeSession as? SpeechAnalyzerCaptureSession
      else {
        result(FlutterError(code: "no_active_session", message: "No transcription session is active", details: nil))
        return
      }
      do {
        try session.resume()
        result(nil)
      } catch {
        fail(result, code: "session_resume_failed", error: error)
      }
    case "cancel":
      guard #available(macOS 26.0, *),
        let session = activeSession as? SpeechAnalyzerCaptureSession
      else {
        result(nil)
        return
      }
      Task {
        await session.cancel()
        activeSession = nil
        complete(result, with: nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func probe(localeIdentifier: String) async -> [String: Any] {
    guard #available(macOS 26.0, *) else {
      return [
        "available": false,
        "platform": "macos-arm64",
        "minimum_os": "macOS 26",
        "locale": localeIdentifier,
        "locale_supported": false,
        "asset_status": "unsupported",
        "reason": "SpeechAnalyzer requires macOS 26 or newer",
      ]
    }
    let requested = localeIdentifier.isEmpty ? Locale.current : Locale(identifier: localeIdentifier)
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
      return [
        "available": false,
        "platform": "macos-arm64",
        "minimum_os": "macOS 26",
        "locale": requested.identifier,
        "locale_supported": false,
        "asset_status": "unsupported",
        "reason": "No equivalent SpeechTranscriber locale is supported",
      ]
    }
    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    let status = await AssetInventory.status(forModules: [transcriber])
    return [
      "available": SpeechTranscriber.isAvailable,
      "platform": "macos-arm64",
      "minimum_os": "macOS 26",
      "locale": locale.identifier,
      "locale_supported": true,
      "asset_status": String(describing: status),
      "reason": SpeechTranscriber.isAvailable
        ? "Apple SpeechAnalyzer is available on device"
        : "SpeechTranscriber is unavailable on this device",
    ]
  }

  private func requestPermissions() async -> Bool {
    let microphone = await AVCaptureDevice.requestAccess(for: .audio)
    guard microphone else { return false }
    let speech = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
    return speech
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.eventSink?(event) }
  }

  private func complete(_ result: @escaping FlutterResult, with value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func fail(_ result: @escaping FlutterResult, code: String, error: Error) {
    complete(
      result,
      with: FlutterError(
        code: code,
        message: error.localizedDescription,
        details: String(describing: error)
      )
    )
  }
}

private enum SpeechBridgeError: LocalizedError {
  case permissionDenied
  case unsupportedOperatingSystem
  case unsupportedLocale
  case unavailableAudioFormat
  case invalidCaptureFormat
  case converterCreationFailed
  case bufferCreationFailed
  case conversionFailed(String)

  var errorDescription: String? {
    switch self {
    case .permissionDenied: "Microphone and speech-recognition permissions are required"
    case .unsupportedOperatingSystem: "SpeechAnalyzer requires macOS 26 or newer"
    case .unsupportedLocale: "The requested transcription locale is unsupported"
    case .unavailableAudioFormat: "No compatible SpeechAnalyzer audio format is installed"
    case .invalidCaptureFormat: "The microphone did not provide a valid audio format"
    case .converterCreationFailed: "Could not create an audio converter"
    case .bufferCreationFailed: "Could not allocate a converted audio buffer"
    case .conversionFailed(let message): "Audio conversion failed: \(message)"
    }
  }
}

@available(macOS 26.0, *)
private final class SpeechAnalyzerCaptureSession: @unchecked Sendable {
  let audioURL: URL

  private let analyzer: SpeechAnalyzer
  private let transcriber: SpeechTranscriber
  private let analyzerFormat: AVAudioFormat
  private let engine = AVAudioEngine()
  private let inputStream: AsyncStream<AnalyzerInput>
  private let inputBuilder: AsyncStream<AnalyzerInput>.Continuation
  private let emit: ([String: Any]) -> Void

  private var audioFile: AVAudioFile?
  private var converter: AVAudioConverter?
  private var analysisTask: Task<Void, Error>?
  private var resultsTask: Task<Void, Error>?
  private var transcript = ""
  private var stopped = false
  private var paused = false
  private var configurationObserver: NSObjectProtocol?

  private init(
    audioURL: URL,
    analyzer: SpeechAnalyzer,
    transcriber: SpeechTranscriber,
    analyzerFormat: AVAudioFormat,
    inputStream: AsyncStream<AnalyzerInput>,
    inputBuilder: AsyncStream<AnalyzerInput>.Continuation,
    emit: @escaping ([String: Any]) -> Void
  ) {
    self.audioURL = audioURL
    self.analyzer = analyzer
    self.transcriber = transcriber
    self.analyzerFormat = analyzerFormat
    self.inputStream = inputStream
    self.inputBuilder = inputBuilder
    self.emit = emit
  }

  static func create(
    directory: URL,
    localeIdentifier: String,
    emit: @escaping ([String: Any]) -> Void
  ) async throws -> SpeechAnalyzerCaptureSession {
    let requested = localeIdentifier.isEmpty ? Locale.current : Locale(identifier: localeIdentifier)
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
      throw SpeechBridgeError.unsupportedLocale
    }
    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      emit(["type": "asset_download_started", "locale": locale.identifier])
      try await request.downloadAndInstall()
      emit(["type": "asset_download_completed", "locale": locale.identifier])
    }
    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
      compatibleWith: [transcriber]
    ) else {
      throw SpeechBridgeError.unavailableAudioFormat
    }
    let analyzer = SpeechAnalyzer(
      modules: [transcriber],
      options: .init(priority: .userInitiated, modelRetention: .lingering)
    )
    try await analyzer.prepareToAnalyze(in: analyzerFormat)

    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let audioURL = directory
      .appendingPathComponent("speech-\(UUID().uuidString.lowercased())")
      .appendingPathExtension("caf")
    let (stream, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
    return SpeechAnalyzerCaptureSession(
      audioURL: audioURL,
      analyzer: analyzer,
      transcriber: transcriber,
      analyzerFormat: analyzerFormat,
      inputStream: stream,
      inputBuilder: builder,
      emit: emit
    )
  }

  func start() throws {
    installConfigurationObserver()
    var engineStarted = false
    defer {
      if !engineStarted {
        removeConfigurationObserver()
      }
    }
    let inputNode = engine.inputNode
    let captureFormat = inputNode.outputFormat(forBus: 0)
    guard
      captureFormat.sampleRate.isFinite,
      captureFormat.sampleRate > 0,
      captureFormat.channelCount > 0
    else {
      removeConfigurationObserver()
      throw SpeechBridgeError.invalidCaptureFormat
    }
    audioFile = try AVAudioFile(
      forWriting: audioURL,
      settings: captureFormat.settings,
      commonFormat: captureFormat.commonFormat,
      interleaved: captureFormat.isInterleaved
    )
    guard let converter = AVAudioConverter(from: captureFormat, to: analyzerFormat) else {
      throw SpeechBridgeError.converterCreationFailed
    }
    self.converter = converter

    resultsTask = Task { [weak self, transcriber] in
      for try await result in transcriber.results {
        guard let self else { return }
        let text = String(result.text.characters)
        if result.isFinal, !text.isEmpty {
          transcript += transcript.isEmpty ? text : " \(text)"
        }
        emit([
          "type": result.isFinal ? "final" : "partial",
          "text": text,
          "start_seconds": result.range.start.seconds,
          "end_seconds": result.range.end.seconds,
        ])
      }
    }
    analysisTask = Task { [analyzer, inputStream] in
      let lastTime = try await analyzer.analyzeSequence(inputStream)
      if let lastTime {
        try await analyzer.finalizeAndFinish(through: lastTime)
      } else {
        await analyzer.cancelAndFinishNow()
      }
    }

    inputNode.installTap(
      onBus: 0,
      bufferSize: 2048,
      format: captureFormat
    ) { [weak self] buffer, _ in
      self?.accept(buffer)
    }
    engine.prepare()
    do {
      try engine.start()
    } catch {
      inputNode.removeTap(onBus: 0)
      removeConfigurationObserver()
      throw error
    }
    engineStarted = true
    emit(["type": "started", "audio_path": audioURL.path])
  }

  func stop() async throws -> [String: Any] {
    guard !stopped else {
      return ["audio_path": audioURL.path, "transcript": transcript]
    }
    stopped = true
    removeConfigurationObserver()
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    inputBuilder.finish()
    try await analysisTask?.value
    try await resultsTask?.value
    audioFile = nil
    emit(["type": "stopped", "audio_path": audioURL.path, "text": transcript])
    return ["audio_path": audioURL.path, "transcript": transcript]
  }

  func pause() {
    guard !stopped, !paused else { return }
    engine.pause()
    paused = true
    emit(["type": "paused", "audio_path": audioURL.path])
  }

  func resume() throws {
    guard !stopped, paused else { return }
    try engine.start()
    paused = false
    emit(["type": "resumed", "audio_path": audioURL.path])
  }

  func cancel() async {
    guard !stopped else { return }
    stopped = true
    removeConfigurationObserver()
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    inputBuilder.finish()
    analysisTask?.cancel()
    resultsTask?.cancel()
    await analyzer.cancelAndFinishNow()
    audioFile = nil
    emit(["type": "cancelled", "audio_path": audioURL.path])
  }

  private func installConfigurationObserver() {
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      guard let self, !stopped else { return }
      engine.pause()
      paused = true
      emit([
        "type": "error",
        "audio_path": audioURL.path,
        "message": "The audio input changed. The partial recording was saved; start a new session to continue.",
      ])
    }
  }

  private func removeConfigurationObserver() {
    guard let configurationObserver else { return }
    NotificationCenter.default.removeObserver(configurationObserver)
    self.configurationObserver = nil
  }

  private func accept(_ buffer: AVAudioPCMBuffer) {
    do {
      try audioFile?.write(from: buffer)
      let converted = try convert(buffer)
      if converted.frameLength > 0 {
        inputBuilder.yield(AnalyzerInput(buffer: converted))
      }
    } catch {
      emit(["type": "error", "message": error.localizedDescription])
    }
  }

  private func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
    guard let converter else { throw SpeechBridgeError.converterCreationFailed }
    let ratio = analyzerFormat.sampleRate / input.format.sampleRate
    let capacity = max(1, AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)))
    guard let output = AVAudioPCMBuffer(
      pcmFormat: analyzerFormat,
      frameCapacity: capacity
    ) else {
      throw SpeechBridgeError.bufferCreationFailed
    }

    var supplied = false
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, status in
      if supplied {
        status.pointee = .noDataNow
        return nil
      }
      supplied = true
      status.pointee = .haveData
      return input
    }
    if status == .error {
      throw SpeechBridgeError.conversionFailed(
        conversionError?.localizedDescription ?? "unknown converter error"
      )
    }
    return output
  }
}

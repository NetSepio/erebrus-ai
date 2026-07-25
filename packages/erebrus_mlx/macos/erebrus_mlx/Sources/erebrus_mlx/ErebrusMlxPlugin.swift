import Cocoa
@preconcurrency import FlutterMacOS
import HuggingFace
import Metal
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

public final class ErebrusMlxPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
  @unchecked Sendable
{
  private var model: ModelContainer?
  private var generationTask: Task<Void, Never>?
  private var eventSink: FlutterEventSink?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ErebrusMlxPlugin()
    let methods = FlutterMethodChannel(
      name: "erebrus_mlx/methods",
      binaryMessenger: registrar.messenger
    )
    let events = FlutterEventChannel(
      name: "erebrus_mlx/events",
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(instance, channel: methods)
    events.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "probe":
      result([
        "available": true,
        "metal_available": MTLCreateSystemDefaultDevice() != nil,
        "platform": "macos-arm64",
        "minimum_os": "macOS 14",
        "reason": "MLX Swift LM 3.31.3 is packaged",
      ])
    case "loadModel":
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["model_directory"] as? String,
        !path.isEmpty
      else {
        result(FlutterError(code: "invalid_arguments", message: "Missing model directory", details: nil))
        return
      }
      loadModel(at: path, result: result)
    case "generate":
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_arguments", message: "Missing generation arguments", details: nil))
        return
      }
      startGeneration(arguments: arguments, result: result)
    case "cancel":
      generationTask?.cancel()
      generationTask = nil
      result(nil)
    case "unload":
      generationTask?.cancel()
      generationTask = nil
      model = nil
      result(nil)
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

  private func loadModel(at path: String, result: @escaping FlutterResult) {
    generationTask?.cancel()
    generationTask = Task { [weak self] in
      do {
        _ = LLMModelFactory.shared
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let loaded = try await MLXLMCommon.loadModelContainer(
          from: directory,
          using: #huggingFaceTokenizerLoader()
        )
        self?.model = loaded
        await MainActor.run { result(nil) }
      } catch {
        await MainActor.run {
          result(
            FlutterError(
              code: "model_load_failed",
              message: error.localizedDescription,
              details: String(describing: error)
            )
          )
        }
      }
    }
  }

  private func startGeneration(arguments: [String: Any], result: @escaping FlutterResult) {
    guard let model else {
      result(FlutterError(code: "model_not_loaded", message: "Load an MLX model first", details: nil))
      return
    }
    guard
      let rawMessages = arguments["messages"] as? [[String: Any]],
      let conversation = makeConversation(rawMessages)
    else {
      result(
        FlutterError(
          code: "invalid_messages",
          message: "MLX requires a non-empty conversation ending in a user message",
          details: nil
        )
      )
      return
    }
    let maxTokens = arguments["max_tokens"] as? Int ?? 256
    let maxKVSize = arguments["max_kv_size"] as? Int ?? 2048
    let temperature = Float(arguments["temperature"] as? Double ?? 0.7)
    let topP = Float(arguments["top_p"] as? Double ?? 0.9)
    let topK = arguments["top_k"] as? Int ?? 40
    let minP = Float(arguments["min_p"] as? Double ?? 0.05)
    let repeatPenalty = Float(arguments["repeat_penalty"] as? Double ?? 1.1)
    let seed = arguments["seed"] as? Int ?? -1

    generationTask?.cancel()
    generationTask = Task { [weak self] in
      do {
        if seed >= 0 { MLXRandom.seed(UInt64(seed)) }
        let parameters = GenerateParameters(
          maxTokens: maxTokens,
          maxKVSize: maxKVSize,
          temperature: temperature,
          topP: topP,
          topK: topK,
          minP: minP,
          repetitionPenalty: repeatPenalty
        )
        let session = ChatSession(
          model,
          instructions: conversation.instructions,
          history: conversation.history,
          generateParameters: parameters
        )
        self?.emit(["type": "started"])
        for try await generation in session.streamDetails(
          to: conversation.prompt,
          images: [],
          videos: []
        ) {
          try Task.checkCancellation()
          switch generation {
          case .chunk(let chunk):
            self?.emit(["type": "token", "text": chunk])
          case .info(let info):
            let reason: String
            switch info.stopReason {
            case .length: reason = "length"
            case .cancelled: reason = "cancelled"
            case .stop: reason = "stop"
            }
            self?.emit([
              "type": "completed",
              "generated_tokens": info.generationTokenCount,
              "prompt_tokens_per_second": info.promptTokensPerSecond,
              "decode_tokens_per_second": info.tokensPerSecond,
              "finish_reason": reason,
            ])
          case .toolCall:
            throw ErebrusMlxError.unsupportedToolCall
          }
        }
      } catch is CancellationError {
        self?.emit(["type": "cancelled"])
      } catch {
        self?.emit([
          "type": "error",
          "message": error.localizedDescription,
        ])
      }
    }
    result(nil)
  }

  private func makeConversation(
    _ values: [[String: Any]]
  ) -> (instructions: String?, history: [Chat.Message], prompt: String)? {
    var instructions: [String] = []
    var messages: [Chat.Message] = []
    for value in values {
      guard
        let rawRole = value["role"] as? String,
        let role = Chat.Message.Role(rawValue: rawRole),
        let content = value["content"] as? String
      else {
        return nil
      }
      if role == .system {
        if !content.isEmpty { instructions.append(content) }
      } else {
        messages.append(Chat.Message(role: role, content: content))
      }
    }
    guard let last = messages.last, last.role == .user else { return nil }
    return (
      instructions.isEmpty ? nil : instructions.joined(separator: "\n\n"),
      Array(messages.dropLast()),
      last.content
    )
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }
}

private enum ErebrusMlxError: LocalizedError {
  case unsupportedToolCall

  var errorDescription: String? {
    "Tool calls are not supported by the Erebrus MLX backend"
  }
}

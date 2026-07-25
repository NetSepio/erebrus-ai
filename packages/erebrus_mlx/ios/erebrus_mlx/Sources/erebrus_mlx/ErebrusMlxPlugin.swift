@preconcurrency import Flutter
import HuggingFace
import Metal
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
import UIKit

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
      binaryMessenger: registrar.messenger()
    )
    let events = FlutterEventChannel(
      name: "erebrus_mlx/events",
      binaryMessenger: registrar.messenger()
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
        "platform": "ios-arm64",
        "minimum_os": "iOS 17",
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
    let prompt = arguments["prompt"] as? String ?? ""
    let systemPrompt = arguments["system_prompt"] as? String
    let maxTokens = arguments["max_tokens"] as? Int ?? 256
    let maxKVSize = arguments["max_kv_size"] as? Int ?? 2048
    let temperature = Float(arguments["temperature"] as? Double ?? 0.7)
    let topP = Float(arguments["top_p"] as? Double ?? 0.9)

    generationTask?.cancel()
    generationTask = Task { [weak self] in
      do {
        let parameters = GenerateParameters(
          maxTokens: maxTokens,
          maxKVSize: maxKVSize,
          temperature: temperature,
          topP: topP
        )
        let session = ChatSession(
          model,
          instructions: systemPrompt?.isEmpty == false ? systemPrompt : nil,
          generateParameters: parameters
        )
        self?.emit(["type": "started"])
        for try await chunk in session.streamResponse(to: prompt) {
          try Task.checkCancellation()
          self?.emit(["type": "token", "text": chunk])
        }
        self?.emit(["type": "completed"])
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

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }
}

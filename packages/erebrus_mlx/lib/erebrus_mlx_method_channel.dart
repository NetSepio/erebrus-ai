import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'erebrus_mlx.dart';
import 'erebrus_mlx_platform_interface.dart';

class MethodChannelErebrusMlx extends ErebrusMlxPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('erebrus_mlx/methods');

  @visibleForTesting
  final eventChannel = const EventChannel('erebrus_mlx/events');

  @override
  Future<MlxProbeResult> probe() async {
    final result = await methodChannel.invokeMapMethod<Object?, Object?>(
      'probe',
    );
    return MlxProbeResult.fromMap(result ?? const {});
  }

  @override
  Future<void> loadModel(String modelDirectory) async {
    await methodChannel.invokeMethod<void>('loadModel', {
      'model_directory': modelDirectory,
    });
  }

  @override
  Stream<MlxGenerationEvent> generate({
    required String prompt,
    required String systemPrompt,
    required int maxTokens,
    required int maxKvSize,
    required double temperature,
    required double topP,
  }) async* {
    final events = eventChannel.receiveBroadcastStream().map(
      (event) =>
          MlxGenerationEvent.fromMap(Map<Object?, Object?>.from(event as Map)),
    );
    final subscription = StreamController<MlxGenerationEvent>();
    final nativeSubscription = events.listen(
      subscription.add,
      onError: subscription.addError,
      onDone: subscription.close,
    );
    try {
      await methodChannel.invokeMethod<void>('generate', {
        'prompt': prompt,
        'system_prompt': systemPrompt,
        'max_tokens': maxTokens,
        'max_kv_size': maxKvSize,
        'temperature': temperature,
        'top_p': topP,
      });
      await for (final event in subscription.stream) {
        yield event;
        if (event.type == 'completed' ||
            event.type == 'cancelled' ||
            event.type == 'error') {
          break;
        }
      }
    } finally {
      await nativeSubscription.cancel();
      if (!subscription.isClosed) await subscription.close();
    }
  }

  @override
  Future<void> cancel() => methodChannel.invokeMethod<void>('cancel');

  @override
  Future<void> unload() => methodChannel.invokeMethod<void>('unload');
}

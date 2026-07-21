import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Handles keeping the device awake and running a foreground service while
/// Erebrus AI is downloading models or serving on the local network.
///
/// On Android this starts a `dataSync` foreground service so work continues
/// when the app is backgrounded. On iOS the service is still started (the
/// plugin keeps a background task alive as long as the OS allows), but the
/// UI also asks the user to keep the app open.
class PowerService {
  PowerService._();
  static final PowerService instance = PowerService._();

  bool _downloadActive = false;
  bool _serving = false;
  bool _initialized = false;

  bool get isBusy => _downloadActive || _serving;

  bool get _inTest => Platform.environment.containsKey('FLUTTER_TEST');

  /// Initialize foreground-task options. Call once before UI paints.
  void initialize() {
    if (_initialized || kIsWeb || _inTest) return;
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'erebrus_foreground',
          channelName: 'Erebrus AI background work',
          channelDescription: 'Keeps model downloads and the local node alive',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
          showBadge: false,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: true,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
        ),
      );
      _initialized = true;
    } on MissingPluginException catch (e) {
      debugPrint('[Power] foreground task plugin not registered: $e');
    } catch (e) {
      debugPrint('[Power] could not initialize foreground task: $e');
    }
  }

  /// Call when a model download starts.
  Future<void> startDownload(String label) async {
    _downloadActive = true;
    await WakelockPlus.enable();
    await _updateOrStart('Downloading $label');
  }

  /// Update the foreground notification with the current download label.
  Future<void> updateDownload(String label, double progress) async {
    final percent = (progress * 100).round();
    await _updateOrStart('Downloading $label · $percent%');
  }

  /// Call when a model download finishes or fails.
  Future<void> stopDownload() async {
    _downloadActive = false;
    if (!_serving) {
      await _stop();
      await WakelockPlus.disable();
    } else {
      await _updateOrStart('Serving on LAN');
    }
  }

  /// Call when the local node serving state changes.
  Future<void> setServing(
    bool serving, {
    String label = 'Serving on LAN',
  }) async {
    _serving = serving;
    if (serving) {
      await WakelockPlus.enable();
      await _updateOrStart(label);
    } else if (!_downloadActive) {
      await _stop();
      await WakelockPlus.disable();
    }
  }

  Future<void> _updateOrStart(String text) async {
    if (kIsWeb || _inTest) return;
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (running) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Erebrus AI',
          notificationText: text,
        );
      } else {
        await FlutterForegroundTask.startService(
          notificationTitle: 'Erebrus AI',
          notificationText: text,
          callback: _foregroundTaskCallback,
        );
      }
    } on MissingPluginException catch (e) {
      debugPrint('[Power] foreground task plugin missing: $e');
    } catch (e) {
      debugPrint('[Power] foreground task error: $e');
    }
  }

  Future<void> _stop() async {
    if (kIsWeb || _inTest) return;
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (running) {
        await FlutterForegroundTask.stopService();
      }
    } on MissingPluginException catch (e) {
      debugPrint('[Power] foreground task plugin missing: $e');
    } catch (e) {
      debugPrint('[Power] foreground task stop error: $e');
    }
  }
}

class _ErebrusTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_ErebrusTaskHandler());
}

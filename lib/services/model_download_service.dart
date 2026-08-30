import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;

import '../data/catalog_entry.dart';
import 'power_service.dart';
import 'storage_service.dart';

/// Downloads model artifacts to persistent storage and tracks progress,
/// both in the UI and as an Android system notification.
class ModelDownloadService extends ChangeNotifier {
  ModelDownloadService._();
  static final ModelDownloadService _instance = ModelDownloadService._();
  static ModelDownloadService get instance => _instance;

  final Map<String, double> _progress = {};
  final Set<String> _completed = {};
  final Set<String> _downloading = {};
  final Set<String> _cancelled = {};
  final Map<String, HttpClient> _activeClients = {};
  final Map<String, int> _receivedBytes = {};
  final Map<String, int> _totalBytes = {};
  final Map<String, int> _lastNotifiedPercent = {};
  final Map<String, String> _ggufPaths = {};
  int _downloadedBytes = 0;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;

  UnmodifiableMapView<String, double> get progress =>
      UnmodifiableMapView(_progress);
  UnmodifiableSetView<String> get completed => UnmodifiableSetView(_completed);
  UnmodifiableSetView<String> get downloading =>
      UnmodifiableSetView(_downloading);
  int get downloadedBytes => _downloadedBytes;

  bool get _inTest => Platform.environment.containsKey('FLUTTER_TEST');

  /// Scans the models directory for existing downloads and completed manifests.
  ///
  /// Also discovers `.gguf` files that were placed there outside the app (e.g.
  /// an existing model folder on the user's desktop). The filename without the
  /// `.gguf` extension is treated as the model id so catalog entries that match
  /// it appear as downloaded.
  Future<void> scanDownloads() async {
    final dir = await StorageService.instance.modelsDir();
    _completed.clear();
    _ggufPaths.clear();
    _downloadedBytes = 0;
    if (!await dir.exists()) {
      notifyListeners();
      return;
    }
    final manifests = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    for (final file in manifests) {
      try {
        final text = await file.readAsString();
        final manifest = json.decode(text) as Map<String, dynamic>;
        final id = manifest['id'] as String?;
        if (id == null || id.isEmpty) continue;
        final modelFile = File(p.join(dir.path, '${_safeName(id)}.gguf'));
        if (!await modelFile.exists()) continue;
        _completed.add(id);
        _ggufPaths[id] = modelFile.path;
      } catch (_) {
        // Ignore corrupt manifest files.
      }
    }

    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.gguf')) {
        continue;
      }
      final name = p.basenameWithoutExtension(entity.path);
      if (name.isEmpty || name.endsWith('_mmproj')) continue;
      _ggufPaths[name] = entity.path;
    }

    await _refreshDownloadedBytes(dir);
    notifyListeners();
  }

  bool isDownloaded(String id) =>
      _completed.contains(id) || _ggufPaths.containsKey(id);

  /// Absolute path to a downloaded GGUF model, or `null` when the download is
  /// incomplete/missing. Native llama.cpp bindings require a real filesystem
  /// path (asset URLs and model ids are not sufficient).
  Future<String?> modelPath(String id) async {
    if (id.isEmpty) return null;
    if (_ggufPaths.containsKey(id)) {
      final existing = File(_ggufPaths[id]!);
      if (await existing.exists()) return existing.path;
      _ggufPaths.remove(id);
    }
    if (!_completed.contains(id)) return null;
    final dir = await StorageService.instance.modelsDir();
    final file = File(p.join(dir.path, '${_safeName(id)}.gguf'));
    if (await file.exists()) return file.path;
    _completed.remove(id);
    notifyListeners();
    return null;
  }

  Future<String?> mmprojPath(String id) async {
    if (id.isEmpty || !_completed.contains(id)) return null;
    final dir = await StorageService.instance.modelsDir();
    final file = File(p.join(dir.path, '${_safeName(id)}_mmproj.gguf'));
    return await file.exists() ? file.path : null;
  }

  double progressOf(String id) => _progress[id] ?? 0.0;
  bool isDownloading(String id) => _downloading.contains(id);
  int receivedBytesOf(String id) => _receivedBytes[id] ?? 0;
  int totalBytesOf(String id) => _totalBytes[id] ?? 0;

  /// Downloads the recommended model artifact (and optional mmproj) for [entry].
  Future<bool> download(CatalogEntry entry) async {
    if (isDownloaded(entry.id)) return true;

    // A denied legacy public-storage permission is not fatal: StorageService
    // falls back to the app-private documents directory on Android.
    await StorageService.instance.ensurePermissions();

    final dir = await StorageService.instance.modelsDir();
    final baseName = _safeName(entry.id);
    final modelFile = File(p.join(dir.path, '$baseName.gguf'));
    final manifestFile = File(p.join(dir.path, '$baseName.json'));

    final mmprojBytes = entry.artifacts
        .where((artifact) => artifact.role == 'mmproj')
        .fold<int>(0, (sum, artifact) => sum + (artifact.sizeBytes ?? 0));
    final totalBytes = entry.sizeBytes + mmprojBytes;
    _downloading.add(entry.id);
    _cancelled.remove(entry.id);
    _progress[entry.id] = 0.0;
    _receivedBytes[entry.id] = 0;
    _totalBytes[entry.id] = totalBytes;
    _lastNotifiedPercent.remove(entry.id);
    notifyListeners();

    await _showNotification('Downloading ${entry.name}', 0.0);
    await PowerService.instance.startDownload(entry.name);

    final ok = await _downloadUrl(
      entry.downloadUrl,
      modelFile,
      entry.id,
      entry.name,
      overallTotal: totalBytes,
    );
    if (!ok) {
      _downloading.remove(entry.id);
      final cancelled = _cancelled.remove(entry.id);
      _receivedBytes.remove(entry.id);
      _totalBytes.remove(entry.id);
      await _showNotification(
        cancelled ? 'Download cancelled' : 'Download failed',
        0.0,
        failed: !cancelled,
      );
      await PowerService.instance.stopDownload();
      notifyListeners();
      return false;
    }

    if (entry.mmprojDownloadUrl.isNotEmpty) {
      final mmprojFile = File(p.join(dir.path, '${baseName}_mmproj.gguf'));
      final mmprojTitle = '${entry.name} (vision)';
      await _showNotification('Downloading $mmprojTitle', 0.0);
      await PowerService.instance.updateDownload(mmprojTitle, 0.0);
      final ok2 = await _downloadUrl(
        entry.mmprojDownloadUrl,
        mmprojFile,
        entry.id,
        mmprojTitle,
        receivedOffset: entry.sizeBytes,
        overallTotal: totalBytes,
      );
      if (!ok2) {
        if (await modelFile.exists()) await modelFile.delete();
        _downloading.remove(entry.id);
        final cancelled = _cancelled.remove(entry.id);
        _progress.remove(entry.id);
        _receivedBytes.remove(entry.id);
        _totalBytes.remove(entry.id);
        notifyListeners();
        await _showNotification(
          cancelled ? 'Download cancelled' : 'Download failed',
          0.0,
          failed: !cancelled,
        );
        await PowerService.instance.stopDownload();
        return false;
      }
    }

    final manifest = {
      'id': entry.id,
      'name': entry.name,
      'family': entry.family,
      'quant': entry.quant,
      'parameterB': entry.parameterB,
      'sizeBytes': entry.sizeBytes,
      'downloadUrl': entry.downloadUrl,
      'mmprojDownloadUrl': entry.mmprojDownloadUrl,
    };
    await manifestFile.writeAsString(json.encode(manifest));

    _completed.add(entry.id);
    _ggufPaths[entry.id] = modelFile.path;
    _downloading.remove(entry.id);
    _cancelled.remove(entry.id);
    _progress[entry.id] = 1.0;
    await _refreshDownloadedBytes(dir);
    notifyListeners();
    await _showNotification('${entry.name} is ready', 1.0, complete: true);
    await PowerService.instance.stopDownload();
    return true;
  }

  Future<void> cancelDownload(String id) async {
    if (!_downloading.contains(id)) return;
    _cancelled.add(id);
    _activeClients.remove(id)?.close(force: true);
    notifyListeners();
  }

  Future<bool> _downloadUrl(
    String url,
    File file,
    String progressId,
    String title, {
    int receivedOffset = 0,
    int overallTotal = 0,
  }) async {
    if (url.isEmpty) return false;
    HttpClient? client;
    IOSink? sink;
    try {
      client = HttpClient();
      _activeClients[progressId] = client;
      client.connectionTimeout = const Duration(seconds: 30);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }

      final total = response.headers.contentLength;
      var received = 0;
      sink = file.openWrite();

      await for (final chunk in response) {
        if (_cancelled.contains(progressId)) {
          throw const HttpException('Download cancelled');
        }
        sink.add(chunk);
        received += chunk.length;
        final overallReceived = receivedOffset + received;
        final knownOverallTotal = overallTotal > 0
            ? overallTotal
            : receivedOffset + total;
        double progress;
        if (knownOverallTotal > 0) {
          progress = overallReceived / knownOverallTotal;
        } else {
          progress = 0.5;
        }
        _progress[progressId] = progress;
        _receivedBytes[progressId] = overallReceived;
        if (knownOverallTotal > 0) {
          _totalBytes[progressId] = knownOverallTotal;
        }
        notifyListeners();
        await _showNotification(title, progress);
        await PowerService.instance.updateDownload(title, progress);
      }
      await sink.close();
      sink = null;
      client.close();
      _activeClients.remove(progressId);
      client = null;
      if (overallTotal <= 0 || receivedOffset + received >= overallTotal) {
        _progress[progressId] = 1.0;
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[Download] error downloading $url: $e');
      try {
        await sink?.close();
      } catch (_) {}
      try {
        await file.delete();
      } catch (_) {}
      client?.close();
      _activeClients.remove(progressId);
      _progress.remove(progressId);
      _lastNotifiedPercent.remove(progressId);
      notifyListeners();
      return false;
    }
  }

  Future<void> _refreshDownloadedBytes(Directory dir) async {
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.gguf')) {
        continue;
      }
      try {
        total += await entity.length();
      } catch (_) {}
    }
    _downloadedBytes = total;
  }

  Future<void> _ensureNotifications() async {
    if (_notificationsReady || _inTest) return;

    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: android);
      await _notifications.initialize(initSettings);

      const channel = AndroidNotificationChannel(
        'model_download_channel',
        'Model downloads',
        description: 'Shows progress while AI models are downloading',
        importance: Importance.low,
        showBadge: false,
      );
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      // Android 13+ notification permission.
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();

      _notificationsReady = true;
    } on MissingPluginException catch (e) {
      debugPrint('[Download] local notifications plugin not registered: $e');
      // Mark ready so we don't retry every tick; downloads still work silently.
      _notificationsReady = true;
    } catch (e) {
      debugPrint('[Download] could not initialize notifications: $e');
      _notificationsReady = true;
    }
  }

  Future<void> _showNotification(
    String title,
    double progress, {
    bool complete = false,
    bool failed = false,
  }) async {
    if (_inTest) return;
    await _ensureNotifications();

    final percent = (progress * 100).round();
    final progressId = title;
    if (!complete && !failed && _lastNotifiedPercent[progressId] == percent) {
      return;
    }
    _lastNotifiedPercent[progressId] = percent;

    final body = complete
        ? 'Download complete and ready to chat'
        : failed
        ? 'Tap to retry from the app'
        : '$percent%';

    final details = AndroidNotificationDetails(
      'model_download_channel',
      'Model downloads',
      channelDescription: 'Shows progress while AI models are downloading',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: !complete && !failed,
      maxProgress: 100,
      progress: complete ? 0 : percent,
      onlyAlertOnce: true,
      ongoing: !complete && !failed,
      autoCancel: complete || failed,
    );

    try {
      await _notifications.show(
        title.hashCode.abs(),
        title,
        body,
        NotificationDetails(android: details),
      );
    } on MissingPluginException catch (e) {
      debugPrint('[Download] cannot show notification: $e');
    } catch (e) {
      debugPrint('[Download] notification error: $e');
    }
  }

  static String _safeName(String id) {
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
  }
}

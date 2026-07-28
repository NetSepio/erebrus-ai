import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent on-device storage for models, chats and personas.
///
/// - Android: prefers a public `ErebrusAI/` folder on external storage so the
///   data survives app uninstall (requires storage permissions).
/// - iOS: stores models under the app documents `ErebrusAI/models` folder,
///   which is exposed to the Files app so other apps can import them.
/// - Desktop (macOS/Windows/Linux): the user may override the models directory
///   via Settings to point at an existing folder of GGUF files.
class StorageService {
  StorageService._();
  static final StorageService _instance = StorageService._();
  static StorageService get instance => _instance;

  static const _kModelsDirPath = 'models_directory_path';
  static const _kModelsDirBookmark = 'models_directory_bookmark';

  String? _customModelsPath;
  Directory? _customModelsDir;
  Directory? _activeSecurityScopedDirectory;

  /// The user-overridden models directory path, or `null` when using the default.
  String? get customModelsPath => _customModelsPath;
  bool get usesCustomModelsDirectory => _customModelsDir != null;

  /// A stable, user-facing location label that does not expose sandbox UUIDs
  /// or other platform-specific absolute paths.
  String get modelsDirectoryDisplayLabel {
    if (!usesCustomModelsDirectory) return 'Default · ErebrusAI/models';
    final rawPath = _customModelsPath ?? _customModelsDir?.path ?? '';
    final folderName = rawPath.isEmpty ? '' : p.basename(p.normalize(rawPath));
    return folderName.isEmpty ? 'Custom folder' : 'Custom · $folderName';
  }

  static bool get supportsCustomModelsDirectory {
    if (kIsWeb) return false;
    return Platform.isAndroid ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux;
  }

  static bool get supportsAppPermissionSettings =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Request permissions required to write the Erebrus AI workspace.
  /// On Android this asks for storage / manage-external-storage; on iOS and
  /// desktop it returns true immediately.
  Future<bool> ensurePermissions() async {
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      // Android 11+ requires MANAGE_EXTERNAL_STORAGE to create a public
      // ErebrusAI folder. On older versions WRITE_EXTERNAL_STORAGE is enough.
      if (await Permission.manageExternalStorage.request().isGranted) {
        return true;
      }
      if (await Permission.storage.request().isGranted) return true;
      return false;
    }
    return true;
  }

  /// Opens the system app settings so the user can grant storage permissions.
  Future<void> openSettings() async {
    if (kIsWeb) return;
    if (!supportsAppPermissionSettings) {
      // Desktop storage uses app-managed folders or a folder picker; there is
      // no permission_handler app-settings channel to invoke.
      debugPrint(
        '[Storage] app permission settings are not required on desktop',
      );
      return;
    }
    try {
      await openAppSettings();
    } on MissingPluginException catch (error) {
      debugPrint('[Storage] permission settings plugin unavailable: $error');
    } on Object catch (error) {
      debugPrint('[Storage] could not open app settings: $error');
    }
  }

  /// Returns the root `ErebrusAI` directory, creating it if needed.
  ///
  /// Requests storage permission on Android and falls back to the app's
  /// private documents directory if the user denies it.
  Future<Directory> baseDir() async {
    final public = await _publicRootDir();
    if (public != null) {
      final dir = Directory(p.join(public.path, 'ErebrusAI'));
      try {
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      } catch (e) {
        debugPrint('[Storage] public dir failed ($e), falling back');
      }
    }
    final fallback = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(fallback.path, 'ErebrusAI'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Returns the models directory. Uses the user-selected folder when one is
  /// set, otherwise the default `ErebrusAI/models` directory.
  Future<Directory> modelsDir() async {
    if (_customModelsDir != null) return _customModelsDir!;
    final dir = Directory(p.join((await baseDir()).path, 'models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// The resolved filesystem path of the current models directory (custom or
  /// default), suitable for display in Settings.
  Future<String> currentModelsDirectoryPath() async {
    return (await modelsDir()).path;
  }

  /// Loads the saved custom models directory on startup.
  Future<void> loadCustomModelsDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_kModelsDirPath);
    final bookmark = prefs.getString(_kModelsDirBookmark);
    if (path == null || path.isEmpty) return;
    final restored = await _setCustomModelsDirectory(path, bookmark: bookmark);
    if (!restored) {
      await prefs.remove(_kModelsDirPath);
      await prefs.remove(_kModelsDirBookmark);
    }
  }

  /// Sets a custom models directory. On macOS a security-scoped bookmark is
  /// created so the sandboxed app keeps access across launches.
  Future<bool> setCustomModelsDirectory(String path) async {
    final dir = Directory(path);
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
    } catch (e) {
      debugPrint('[Storage] could not create $path: $e');
      return false;
    }

    String? bookmark;
    if (!kIsWeb && Platform.isMacOS) {
      try {
        bookmark = await SecureBookmarks().bookmark(dir);
      } catch (e) {
        debugPrint('[Storage] could not create bookmark for $path: $e');
        return false;
      }
    }
    final activated = await _setCustomModelsDirectory(path, bookmark: bookmark);
    if (!activated) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModelsDirPath, path);
    if (bookmark != null) {
      await prefs.setString(_kModelsDirBookmark, bookmark);
    } else {
      await prefs.remove(_kModelsDirBookmark);
    }
    return true;
  }

  /// Returns to the app-managed models directory and releases any active
  /// macOS security-scoped resource.
  Future<void> resetModelsDirectory() async {
    await _stopAccessingCurrentDirectory();
    _customModelsDir = null;
    _customModelsPath = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kModelsDirPath);
    await prefs.remove(_kModelsDirBookmark);
  }

  Future<bool> _setCustomModelsDirectory(
    String path, {
    String? bookmark,
  }) async {
    final dir = Directory(path);
    if (!kIsWeb && Platform.isMacOS) {
      if (bookmark == null || bookmark.isEmpty) return false;
      try {
        final resolved = await SecureBookmarks().resolveBookmark(
          bookmark,
          isDirectory: true,
        );
        if (resolved is Directory) {
          final started = await SecureBookmarks()
              .startAccessingSecurityScopedResource(resolved);
          if (!started) return false;
          if (!await resolved.exists()) {
            await SecureBookmarks().stopAccessingSecurityScopedResource(
              resolved,
            );
            return false;
          }
          await _stopAccessingCurrentDirectory();
          _activeSecurityScopedDirectory = resolved;
          _customModelsDir = resolved;
          _customModelsPath = path;
          return true;
        }
      } catch (e) {
        debugPrint('[Storage] could not resolve bookmark for $path: $e');
      }
      return false;
    }

    if (!await dir.exists()) return false;
    await _stopAccessingCurrentDirectory();
    _customModelsDir = dir;
    _customModelsPath = path;
    return true;
  }

  Future<void> _stopAccessingCurrentDirectory() async {
    final active = _activeSecurityScopedDirectory;
    _activeSecurityScopedDirectory = null;
    if (active == null || kIsWeb || !Platform.isMacOS) return;
    try {
      await SecureBookmarks().stopAccessingSecurityScopedResource(active);
    } catch (e) {
      debugPrint('[Storage] could not release ${active.path}: $e');
    }
  }

  Future<Directory> chatsDir() async {
    final dir = Directory(p.join((await baseDir()).path, 'chats'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> personasDir() async {
    final dir = Directory(p.join((await baseDir()).path, 'personas'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> transcriptionsDir() async {
    final dir = Directory(p.join((await baseDir()).path, 'transcriptions'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> asrModelsDir() async {
    final dir = Directory(p.join((await baseDir()).path, 'asr-models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> telemetryDir() async {
    final dir = Directory(p.join((await baseDir()).path, 'telemetry'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Returns the public external storage root on Android when permission has
  /// already been granted, or null if we should fall back to app-private
  /// storage. This does *not* request permission — that is done when the user
  /// starts a download so the storage scan at startup does not pop a dialog.
  Future<Directory?> _publicRootDir() async {
    if (!Platform.isAndroid) return null;

    final storage = await Permission.storage.status;
    final manage = await Permission.manageExternalStorage.status;
    if (!storage.isGranted && !manage.isGranted) return null;

    final ext = await getExternalStorageDirectory();
    if (ext == null) return null;

    // getExternalStorageDirectory usually returns something like
    // /storage/emulated/0/Android/data/<pkg>/files. Walk up past the
    // Android/ sandbox to the public volume root (/storage/emulated/0).
    var root = ext;
    while (root.path.contains('/Android/')) {
      root = root.parent;
    }
    return root;
  }
}

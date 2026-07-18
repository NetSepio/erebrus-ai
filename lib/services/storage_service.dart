import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Persistent on-device storage for models, chats and personas.
///
/// - Android: prefers a public `ErebrusAI/` folder on external storage so the
///   data survives app uninstall (requires storage permissions).
/// - iOS / desktop: uses the app's documents directory as a persistent,
///   user-accessible workspace.
class StorageService {
  StorageService._();
  static final StorageService _instance = StorageService._();
  static StorageService get instance => _instance;

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
    await openAppSettings();
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

  Future<Directory> modelsDir() async {
    final dir = Directory(p.join((await baseDir()).path, 'models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:system_info2/system_info2.dart';

/// Broad device class used for model recommendations.
enum DeviceType { mobile, desktop }

/// Snapshot of the device the app is running on.
class DeviceProfile {
  const DeviceProfile({
    required this.type,
    required this.ramBytes,
    required this.name,
    required this.platform,
  });

  final DeviceType type;
  final int ramBytes;
  final String name;

  /// Platform identifier matching the catalog, e.g. `macos-arm64`.
  final String platform;

  double get ramGB => ramBytes / (1024 * 1024 * 1024);
}

/// Detects total RAM and a human-readable device name.
///
/// Falls back to a conservative 8 GB profile if the platform helpers fail.
class DeviceInfoService {
  static DeviceProfile detect() {
    var ramBytes = 8 * 1024 * 1024 * 1024; // 8 GB fallback
    try {
      ramBytes = SysInfo.getTotalPhysicalMemory();
    } catch (_) {
      // Keep fallback.
    }
    if (ramBytes <= 0) ramBytes = 8 * 1024 * 1024 * 1024;

    var type = DeviceType.desktop;
    var name = SysInfo.operatingSystemName;
    String os;

    if (kIsWeb) {
      type = DeviceType.mobile;
      name = 'Web';
      os = 'web';
    } else if (Platform.isAndroid) {
      type = DeviceType.mobile;
      os = 'android';
    } else if (Platform.isIOS) {
      type = DeviceType.mobile;
      os = 'ios';
    } else if (Platform.isMacOS) {
      type = DeviceType.desktop;
      os = 'macos';
    } else if (Platform.isWindows) {
      type = DeviceType.desktop;
      os = 'windows';
    } else if (Platform.isLinux) {
      type = DeviceType.desktop;
      os = 'linux';
    } else {
      os = 'unknown';
    }

    var arch = _detectArchitecture();
    if (arch == 'unknown' || arch.isEmpty) {
      if (os == 'android' || os == 'ios' || os == 'macos' || os == 'web') {
        arch = 'arm64';
      } else {
        arch = 'x86_64';
      }
    }
    final platform = '$os-$arch';

    return DeviceProfile(
        type: type, ramBytes: ramBytes, name: name, platform: platform);
  }

  static String _detectArchitecture() {
    try {
      final raw = SysInfo.kernelArchitecture.name.toLowerCase();
      if (raw.contains('arm64') || raw.contains('aarch64')) return 'arm64';
      if (raw.contains('x86_64') || raw.contains('amd64')) return 'x86_64';
      if (raw.contains('i386') || raw.contains('i686') || raw == 'x86') {
        return 'x86';
      }
      if (raw.contains('arm')) return 'arm';
    } catch (_) {
      // Fall through to unknown.
    }
    return 'unknown';
  }
}

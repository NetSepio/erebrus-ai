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
      ramBytes = _physicalMemoryBytes();
    } catch (_) {
      // Keep fallback.
    }
    if (ramBytes <= 0) ramBytes = 8 * 1024 * 1024 * 1024;

    var type = DeviceType.desktop;
    String name;
    String os;

    if (kIsWeb) {
      type = DeviceType.mobile;
      name = 'Web';
      os = 'web';
    } else if (Platform.isAndroid) {
      type = DeviceType.mobile;
      name = _systemInfoOsName(fallback: 'Android');
      os = 'android';
    } else if (Platform.isIOS) {
      type = DeviceType.mobile;
      name = Platform.operatingSystemVersion.isNotEmpty
          ? 'iOS ${Platform.operatingSystemVersion}'
          : 'iOS';
      os = 'ios';
    } else if (Platform.isMacOS) {
      type = DeviceType.desktop;
      name = _systemInfoOsName(fallback: 'macOS');
      os = 'macos';
    } else if (Platform.isWindows) {
      type = DeviceType.desktop;
      name = _systemInfoOsName(fallback: 'Windows');
      os = 'windows';
    } else if (Platform.isLinux) {
      type = DeviceType.desktop;
      name = _systemInfoOsName(fallback: 'Linux');
      os = 'linux';
    } else {
      name = _systemInfoOsName(fallback: 'Unknown');
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
      type: type,
      ramBytes: ramBytes,
      name: name,
      platform: platform,
    );
  }

  static int _physicalMemoryBytes() {
    if (!kIsWeb && Platform.isMacOS) {
      // system_info2 4.1.0 multiplies hw.memsize (already expressed in bytes)
      // by hw.pagesize on macOS. Read the kernel value directly until that
      // upstream implementation is corrected.
      try {
        final result = Process.runSync('/usr/sbin/sysctl', const [
          '-n',
          'hw.memsize',
        ]);
        if (result.exitCode == 0) {
          final bytes = int.tryParse(result.stdout.toString().trim());
          if (bytes != null && bytes > 0) return bytes;
        }
      } catch (_) {
        // Fall back to the package result and repair its known unit error.
      }
    }

    final reportedBytes = SysInfo.getTotalPhysicalMemory();
    if (!kIsWeb && Platform.isMacOS) {
      var pageSizeBytes = 16 * 1024;
      try {
        final result = Process.runSync('/usr/sbin/sysctl', const [
          '-n',
          'hw.pagesize',
        ]);
        if (result.exitCode == 0) {
          pageSizeBytes =
              int.tryParse(result.stdout.toString().trim()) ?? pageSizeBytes;
        }
      } catch (_) {
        // Apple Silicon uses 16 KB pages; the direct hw.memsize path above
        // handles Intel Macs whenever sysctl is available.
      }
      return normalizeMacOSMemoryBytes(
        reportedBytes,
        pageSizeBytes: pageSizeBytes,
      );
    }
    return reportedBytes;
  }

  @visibleForTesting
  static int normalizeMacOSMemoryBytes(
    int reportedBytes, {
    int pageSizeBytes = 16 * 1024,
  }) {
    const plausibleConsumerMacMaximum = 1024 * 1024 * 1024 * 1024; // 1 TB
    if (reportedBytes > plausibleConsumerMacMaximum && pageSizeBytes > 0) {
      return reportedBytes ~/ pageSizeBytes;
    }
    return reportedBytes;
  }

  static String _systemInfoOsName({required String fallback}) {
    try {
      return SysInfo.operatingSystemName;
    } catch (_) {
      return fallback;
    }
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

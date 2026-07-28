import 'package:erebrus_ai/services/device_info_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceInfoService macOS memory normalization', () {
    test('repairs the system_info2 Apple Silicon page-size multiplier', () {
      const actualBytes = 24 * 1024 * 1024 * 1024;
      const appleSiliconPageSize = 16 * 1024;

      expect(
        DeviceInfoService.normalizeMacOSMemoryBytes(
          actualBytes * appleSiliconPageSize,
          pageSizeBytes: appleSiliconPageSize,
        ),
        actualBytes,
      );
    });

    test('repairs the system_info2 Intel page-size multiplier', () {
      const actualBytes = 32 * 1024 * 1024 * 1024;
      const intelPageSize = 4 * 1024;

      expect(
        DeviceInfoService.normalizeMacOSMemoryBytes(
          actualBytes * intelPageSize,
          pageSizeBytes: intelPageSize,
        ),
        actualBytes,
      );
    });

    test('leaves an already-correct value unchanged', () {
      const actualBytes = 64 * 1024 * 1024 * 1024;

      expect(
        DeviceInfoService.normalizeMacOSMemoryBytes(actualBytes),
        actualBytes,
      );
    });
  });
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypts persisted app secrets at rest (gateway session token, stored keys).
/// Uses the plugin's default cipher (RSA-OAEP key wrapping + AES-GCM data),
/// which is explicitly non-biometric — secrets read/write silently.
class ErebrusSecureStorage {
  const ErebrusSecureStorage._();

  /// App-specific, non-synchronizing namespace for rotating session secrets.
  /// No shared access group and no cloud/device migration of refresh tokens.
  static const FlutterSecureStorage sessions = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'io.erebrus.ai.auth.v2',
      resetOnError: false,
    ),
    iOptions: IOSOptions(
      accountName: 'io.erebrus.ai.auth.v2',
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accountName: 'io.erebrus.ai.auth.v2',
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const FlutterSecureStorage instance = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      migrateOnAlgorithmChange: true,
    ),
  );
}

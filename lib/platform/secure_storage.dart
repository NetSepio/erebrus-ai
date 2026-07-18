import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypts persisted app secrets at rest (gateway session token, stored keys).
/// Uses the plugin's default cipher (RSA-OAEP key wrapping + AES-GCM data),
/// which is explicitly non-biometric — secrets read/write silently.
class ErebrusSecureStorage {
  const ErebrusSecureStorage._();

  static const FlutterSecureStorage instance = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
      migrateOnAlgorithmChange: true,
    ),
  );
}

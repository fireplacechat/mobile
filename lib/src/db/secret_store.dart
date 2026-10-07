import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small key/value store for secrets (private keys, session state, pinned identities).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Removes everything (account deletion).
  Future<void> clear();
}

/// iOS Keychain / Android Keystore backed store.
class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage(iOptions: iosOptions);
  final FlutterSecureStorage _s;

  /// Keep new iOS items non-migratable without widening locked-device access.
  /// Background key access needs a separate decision before it is enabled.
  static const iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  );

  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);

  /// Intentional whole-install reset, including any old account's key remnants.
  /// Do not replace with guessed UID prefixes: session keys also use device IDs.
  /// Revisit deletion isolation before supporting concurrent local accounts.
  @override
  Future<void> clear() => _s.deleteAll();
}

/// For tests.
class MemorySecretStore implements SecretStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
  @override
  Future<void> clear() async => data.clear();
}

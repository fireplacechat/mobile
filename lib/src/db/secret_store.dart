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

/// Remembers what it read and wrote, so reading the same key again does not
/// go back to the platform store: every Keychain call is a slow round trip
/// through the platform, and receiving one message used about ten of them.
///
/// Writes still go to the store every time. A value is remembered only after
/// the store confirmed it; a failed write forgets the key, so the next read
/// asks the store again. Only one instance may own a key: changes made
/// through another instance or the store itself are not seen until [forget].
class CachedSecretStore implements SecretStore {
  CachedSecretStore(this._store);
  final SecretStore _store;
  final _values = <String, String?>{};

  /// Changes started per key. A read or change remembers its result only if
  /// no other change to that key started meanwhile.
  final _changes = <String, int>{};

  /// Raised by [forget]: a read or change that started before it does not
  /// remember its result.
  int _epoch = 0;

  @override
  Future<String?> read(String key) async {
    if (_values.containsKey(key)) return _values[key];
    final seen = _changes[key] ?? 0;
    final epoch = _epoch;
    final value = await _store.read(key);
    if ((_changes[key] ?? 0) == seen && _epoch == epoch) _values[key] = value;
    return value;
  }

  @override
  Future<void> write(String key, String value) =>
      _change(key, value, () => _store.write(key, value));

  @override
  Future<void> delete(String key) =>
      _change(key, null, () => _store.delete(key));

  Future<void> _change(
    String key,
    String? value,
    Future<void> Function() store,
  ) async {
    final mine = (_changes[key] ?? 0) + 1;
    _changes[key] = mine;
    final epoch = _epoch;
    _values.remove(key);
    await store();
    if (_changes[key] == mine && _epoch == epoch) _values[key] = value;
  }

  /// Forgets everything remembered, so the next reads go to the store. Called
  /// when another isolate may have changed the store (decision 0030). A read
  /// already under way does not remember its result either.
  void forget() {
    _epoch++;
    _values.clear();
  }

  @override
  Future<void> clear() async {
    for (final key in {..._values.keys, ..._changes.keys}) {
      _changes[key] = (_changes[key] ?? 0) + 1;
    }
    _values.clear();
    await _store.clear();
  }
}

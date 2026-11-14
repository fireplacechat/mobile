import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fireplace/src/db/ios_shared_storage.dart';

/// Small key/value store for secrets (private keys, session state, pinned identities).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Snapshot used only for account-scoped erasure and legacy preferences.
  /// Values never leave the device and must never be logged.
  Future<Map<String, String>> readAll();

  /// Explicit whole-install reset only. Account deletion must erase by owner.
  Future<void> clear();
}

/// iOS Keychain / Android Keystore backed store.
class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage]) : _injected = storage;
  final FlutterSecureStorage? _injected;
  Future<FlutterSecureStorage>? _configured;

  /// After the first unlock, previews can read while locked (0035). Items
  /// remain device-only and are never synchronised through iCloud.
  static const iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  Future<FlutterSecureStorage> _store() async {
    if (_injected != null) return _injected;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const FlutterSecureStorage(iOptions: iosOptions);
    }
    return _configured ??= _configureIos();
  }

  Future<FlutterSecureStorage> _configureIos() async {
    try {
      final shared = await IosSharedStorage.prepare();
      return FlutterSecureStorage(
        iOptions: IOSOptions(
          groupId: shared.keychainGroup,
          accessibility: KeychainAccessibility.first_unlock_this_device,
          synchronizable: false,
        ),
      );
    } catch (_) {
      _configured =
          null; // A failed migration never falls back to an empty store.
      rethrow;
    }
  }

  @override
  Future<String?> read(String key) async => (await _store()).read(key: key);
  @override
  Future<void> write(String key, String value) async =>
      (await _store()).write(key: key, value: value);
  @override
  Future<void> delete(String key) async => (await _store()).delete(key: key);

  @override
  Future<Map<String, String>> readAll() async => (await _store()).readAll();

  /// Whole-install reset. Never use for deleting a single account: session
  /// keys also use device IDs, and another account may share this store.
  @override
  Future<void> clear() async => (await _store()).deleteAll();
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
  Future<Map<String, String>> readAll() async => Map.of(data);
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

  @override
  Future<Map<String, String>> readAll() => _store.readAll();

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

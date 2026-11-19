import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/db/secret_store.dart';

/// What a wrapped value starts with (decision 0033).
const wrappedSecretPrefix = 'fpl1:';

/// A wrapped item was asked for while the passphrase lock is closed.
class SecretsLocked implements Exception {
  const SecretsLocked();
  @override
  String toString() => 'Local data is locked.';
}

/// Whether the passphrase lock wraps the secure-store item [name] of account
/// [uid] on device [deviceId]: everything that decrypts a message, a session
/// or a name (decision 0033, "What is wrapped").
bool lockWrapsItem(String name, String uid, String deviceId) =>
    name == 'msgkey:$uid' ||
    name == 'chatprefskey:$uid' ||
    name == 'groupkey:$uid' ||
    name == 'identity:$uid' ||
    name == 'device:$uid' ||
    name.startsWith('prekeys:$uid:') ||
    name.startsWith('sess:$deviceId:') ||
    name == 'journal:$deviceId' ||
    name == 'journals:$deviceId' ||
    name.startsWith('journal:$deviceId:');

/// The app's secret store with the passphrase lock (decision 0033) in front of
/// it. Values that start with [wrappedSecretPrefix] are AES-256-GCM under the
/// account's data key, with the item's name as associated data; every other
/// value passes through as it is, so an account without the lock, and an
/// item not yet rewritten while the lock is being turned on or off, read as
/// before.
///
/// Writes to one item are made one at a time, so [rewrite] cannot put back a
/// value older than one written meanwhile through this store. Other isolates
/// are kept out by the caller (the account lock).
class WrappingSecretStore implements SecretStore {
  WrappingSecretStore(this._inner);
  final SecretStore _inner;
  _Open? _open;
  final _queues = <String, Future<void>>{};

  static final _aes = AesGcm.with256bits();

  /// Whether a data key is held.
  bool get isOpen => _open != null;

  /// The account whose data key is held, or null.
  String? get openAccount => _open?.uid;

  /// Holds [dataKey] for the items of [uid] on [deviceId]. With [wrapWrites],
  /// what is written to them from now on is wrapped.
  void open({
    required String uid,
    required String deviceId,
    required List<int> dataKey,
    required bool wrapWrites,
  }) {
    if (dataKey.length != 32) throw ArgumentError('Bad data key.');
    _open = _Open(uid, deviceId, SecretKey(List.of(dataKey)), wrapWrites);
  }

  /// Turning the lock off: from now on writes are plain again.
  void stopWrapping() {
    final open = _open;
    if (open != null) _open = _Open(open.uid, open.deviceId, open.key, false);
  }

  /// Forgets the data key. Wrapped items cannot be read until [open].
  void close() => _open = null;

  Future<T> _serial<T>(String key, Future<T> Function() action) {
    final before = _queues[key] ?? Future<void>.value();
    final run = before.then((_) => action());
    final done = run.then<void>((_) {}, onError: (Object _) {});
    _queues[key] = done;
    unawaited(
      done.whenComplete(() {
        if (identical(_queues[key], done)) _queues.remove(key);
      }),
    );
    return run;
  }

  Future<String> _wrap(_Open open, String key, String value) async {
    final box = await _aes.encrypt(
      utf8.encode(value),
      secretKey: open.key,
      aad: utf8.encode(key),
    );
    return '$wrappedSecretPrefix${b64(box.concatenation())}';
  }

  Future<String> _unwrap(_Open open, String key, String value) async {
    final bytes = unb64(value.substring(wrappedSecretPrefix.length));
    final box = SecretBox.fromConcatenation(
      bytes,
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    final clear = await _aes.decrypt(
      box,
      secretKey: open.key,
      aad: utf8.encode(key),
    );
    return utf8.decode(clear);
  }

  Future<String?> _shown(String key, String? value) async {
    if (value == null || !value.startsWith(wrappedSecretPrefix)) return value;
    final open = _open;
    if (open == null || !open.covers(key)) throw const SecretsLocked();
    return _unwrap(open, key, value);
  }

  @override
  Future<String?> read(String key) async => _shown(key, await _inner.read(key));

  @override
  Future<void> write(String key, String value) => _serial(key, () async {
    final open = _open;
    await _inner.write(
      key,
      open != null && open.wrapWrites && open.covers(key)
          ? await _wrap(open, key, value)
          : value,
    );
  });

  @override
  Future<void> delete(String key) => _serial(key, () => _inner.delete(key));

  /// Wrapped values that can be opened are given opened; any other wrapped
  /// value is given as stored, which is enough for erasure by name.
  @override
  Future<Map<String, String>> readAll() async {
    final all = await _inner.readAll();
    final open = _open;
    return {
      for (final entry in all.entries)
        entry.key:
            entry.value.startsWith(wrappedSecretPrefix) &&
                open != null &&
                open.covers(entry.key)
            ? await _unwrap(open, entry.key, entry.value)
            : entry.value,
    };
  }

  @override
  Future<void> clear() => _inner.clear();

  /// The names of the open account's items the lock wraps.
  Future<List<String>> coveredItems() async {
    final open = _open;
    if (open == null) throw const SecretsLocked();
    return [
      for (final name in (await _inner.readAll()).keys)
        if (open.covers(name)) name,
    ];
  }

  /// Rewrites [key] wrapped or plain, as [wrapped] says, in its turn with
  /// other writes to it. Does nothing to an item already in that form, or
  /// gone. Needs the data key.
  Future<void> rewrite(String key, {required bool wrapped}) =>
      _serial(key, () async {
        final open = _open;
        if (open == null) throw const SecretsLocked();
        final value = await _inner.read(key);
        if (value == null) return;
        final isWrapped = value.startsWith(wrappedSecretPrefix);
        if (isWrapped == wrapped) return;
        await _inner.write(
          key,
          wrapped
              ? await _wrap(open, key, value)
              : await _unwrap(open, key, value),
        );
      });

  /// Wrapping and opening, for the lock record's data key.
  static Future<String> seal(
    List<int> key,
    List<int> value,
    String label,
  ) async {
    final box = await _aes.encrypt(
      value,
      secretKey: SecretKey(List.of(key)),
      aad: utf8.encode(label),
    );
    return b64(box.concatenation());
  }

  /// Opens what [seal] made, or throws [SecretBoxAuthenticationError] when
  /// the key is not the one it was sealed with.
  static Future<Uint8List> unseal(
    List<int> key,
    String sealed,
    String label,
  ) async {
    final box = SecretBox.fromConcatenation(
      unb64(sealed),
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    return Uint8List.fromList(
      await _aes.decrypt(
        box,
        secretKey: SecretKey(List.of(key)),
        aad: utf8.encode(label),
      ),
    );
  }
}

class _Open {
  _Open(this.uid, this.deviceId, this.key, this.wrapWrites);
  final String uid, deviceId;
  final SecretKey key;
  final bool wrapWrites;
  bool covers(String name) => lockWrapsItem(name, uid, deviceId);
}

import 'package:fireplace/src/db/secret_store.dart';

/// Appearance and send sound are local, but belong to one account. Older
/// installs shared these three choices. Copy that inherited choice to each
/// local account before removing the legacy keys; never reset another user.
class AccountPreferences {
  AccountPreferences(this.store);
  final SecretStore store;
  static const legacyKeys = [
    'ui:theme-mode',
    'ui:chat-colors',
    'ui:send-sound',
  ];
  static String key(String base, String? uid) =>
      uid == null ? base : '$base:account:$uid';
  Future<void> _changes = Future.value();
  final _deleting = <String>{};

  Future<void> _run(Future<void> Function() action) {
    final next = _changes.then((_) => action());
    _changes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _migrate(String uid) async {
    final legacy = <String, String>{};
    for (final base in legacyKeys) {
      final value = await store.read(base);
      if (value != null) legacy[base] = value;
    }
    if (legacy.isEmpty) return;
    final snapshot = await store.readAll();
    final owners = <String>{uid};
    for (final name in snapshot.keys) {
      for (final prefix in ['identity:', 'device:', 'bundle:', 'msgkey:']) {
        if (name.startsWith(prefix)) owners.add(name.substring(prefix.length));
      }
    }
    for (final owner in owners) {
      if (_deleting.contains(owner)) continue;
      for (final entry in legacy.entries) {
        final target = key(entry.key, owner);
        if (!snapshot.containsKey(target)) {
          await store.write(target, entry.value);
        }
      }
    }
    // A failed copy leaves the legacy values available for a retry.
    for (final base in legacy.keys) {
      await store.delete(base);
    }
  }

  Future<String?> read(String base, String? uid) async {
    if (uid != null) await _run(() => _migrate(uid));
    if (uid != null && _deleting.contains(uid)) return null;
    return store.read(key(base, uid));
  }

  Future<void> write(String base, String? uid, String value) => _run(() async {
    if (uid != null) {
      if (_deleting.contains(uid)) {
        throw StateError('Account is being deleted.');
      }
      await _migrate(uid);
    }
    await store.write(key(base, uid), value);
  });

  /// Drain already-started writes before erasure; reject any later choice.
  Future<void> deleting(String uid) async {
    _deleting.add(uid);
    await _run(() => _migrate(uid));
  }
}

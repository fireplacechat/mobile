import 'dart:async';

import 'package:fireplace/src/crypto/device.dart';
import 'package:fireplace/src/model/keys/key_service.dart';

/// Verified device lists of the accounts this device sends to, kept current
/// by a live listener, so a send does not read them from the server first.
///
/// Signal's apps do the same: they send to the devices they know, and the
/// server answers with the missing and extra devices when that list is out of
/// date. Firestore rules cannot answer like that, so the listener keeps the
/// list fresh instead. A device added a moment ago can still miss one message;
/// it shows "Sent before this device was added", as before.
///
/// Costs one read per listed device when a listener starts and one per change;
/// devices are immutable apart from revocation, so changes are rare. At most
/// [capacity] listeners run; the least recently used one stops first.
class DeviceCache {
  DeviceCache(
    this._keys, {
    this.capacity = 32,
    this.firstWait = const Duration(seconds: 4),
  });

  final KeyService _keys;
  final int capacity;

  /// How long a send waits for a new listener's first server snapshot before
  /// it reads the list directly, as it did before (for example offline).
  final Duration firstWait;

  // Insertion order is recency: a use moves the entry to the end.
  final _entries = <String, _Entry>{};
  bool _closed = false;

  /// Starts listening to [uid]'s devices so the first send finds them ready.
  void warm(String uid) {
    if (!_closed) _touch(uid);
  }

  Future<List<DeviceBundle>> devices(String uid) async {
    if (_closed) return _keys.fetchDevices(uid);
    final entry = _touch(uid);
    if (!entry.ready.isCompleted) {
      await entry.ready.future.timeout(firstWait, onTimeout: () {});
    }
    final latest = entry.latest;
    // A changed identity is checked again on every send, so the send after the
    // person trusts the new key goes through; the fresh read throws again
    // while the change is still waiting for them.
    if (latest == null || entry.identityChanged) {
      if (entry.identityChanged) _forget(uid);
      return _keys.fetchDevices(uid);
    }
    return latest;
  }

  _Entry _touch(String uid) {
    final existing = _entries.remove(uid);
    if (existing != null) return _entries[uid] = existing;
    while (_entries.length >= capacity) {
      _forget(_entries.keys.first);
    }
    final entry = _Entry();
    _entries[uid] = entry;
    entry.sub = _keys
        .watchDevices(uid)
        .listen(
          (list) {
            entry
              ..latest = list
              ..identityChanged = false;
            if (!entry.ready.isCompleted) entry.ready.complete();
          },
          onError: (Object e) {
            if (e is IdentityChangedException) {
              entry.identityChanged = true;
              if (!entry.ready.isCompleted) entry.ready.complete();
              return;
            }
            // The listener ended: forget it, and the next send reads directly.
            if (identical(_entries[uid], entry)) _forget(uid);
            if (!entry.ready.isCompleted) entry.ready.complete();
          },
        );
    return entry;
  }

  void _forget(String uid) {
    final entry = _entries.remove(uid);
    unawaited(entry?.sub?.cancel());
  }

  Future<void> close() async {
    _closed = true;
    final entries = _entries.values.toList();
    _entries.clear();
    for (final e in entries) {
      await e.sub?.cancel();
    }
  }
}

class _Entry {
  final ready = Completer<void>();
  StreamSubscription<List<DeviceBundle>>? sub;
  List<DeviceBundle>? latest;
  bool identityChanged = false;
}

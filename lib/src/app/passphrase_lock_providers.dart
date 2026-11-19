import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/wrapping_secret_store.dart';
import 'package:fireplace/src/model/lock/passphrase_lock.dart';

/// The app's secret store, when it is the one with the passphrase lock in
/// front (not in tests that give a plain store).
final wrappingSecretStoreProvider = Provider<WrappingSecretStore?>((ref) {
  final store = ref.watch(secretStoreProvider);
  return store is WrappingSecretStore ? store : null;
});

final passphraseLockServiceProvider = Provider<PassphraseLock?>((ref) {
  final store = ref.watch(wrappingSecretStoreProvider);
  return store == null ? null : PassphraseLock(store);
});

/// The signed-in account's data is locked: the passphrase opens it.
class PassphraseLocked implements Exception {
  const PassphraseLocked();
  @override
  String toString() => 'Fireplace is locked.';
}

/// The passphrase lock of the signed-in account (decision 0033).
class LockState {
  const LockState({
    required this.on,
    required this.open,
    this.autoLock = AutoLock.standard,
  });
  static const off = LockState(on: false, open: false);

  /// The lock is set for this account.
  final bool on;

  /// Its data key is held: the app can read the account's data.
  final bool open;
  final AutoLock autoLock;

  bool get locked => on && !open;
}

class PassphraseLockController extends AsyncNotifier<LockState> {
  String? get _uid => ref.read(preferencesUidProvider);
  PassphraseLock? get _lock => ref.read(passphraseLockServiceProvider);

  @override
  Future<LockState> build() async {
    final uid = ref.watch(preferencesUidProvider);
    final lock = ref.watch(passphraseLockServiceProvider);
    if (uid == null || lock == null) return LockState.off;
    return _read(lock, uid);
  }

  Future<LockState> _read(PassphraseLock lock, String uid) async {
    final record = await lock.record(uid);
    if (record == null) return LockState.off;
    return LockState(
      on: true,
      open: lock.isOpen(uid),
      autoLock: record.autoLock,
    );
  }

  Future<void> _refresh() async {
    final uid = _uid, lock = _lock;
    if (uid == null || lock == null || !ref.mounted) return;
    final next = await _read(lock, uid);
    if (ref.mounted) state = AsyncData(next);
  }

  /// Runs [work] holding the account's lock, which the session and the
  /// background push handler share, so neither writes a session meanwhile.
  Future<void> _exclusive(Future<void> Function() work) async {
    final lock = ref.read(appSessionProvider).value?.lock;
    if (lock == null) return work();
    await lock.run(work);
  }

  /// Opens the data with [passphrase]. False for a wrong one. A change that
  /// was stopped half-way is finished first. Before any session starts,
  /// previews are already off, so no other isolate opens the stores.
  Future<bool> unlock(String passphrase) async {
    final uid = _uid, lock = _lock;
    if (uid == null || lock == null) return false;
    if (!await lock.unlock(uid, passphrase)) return false;
    await lock.finishPending(uid, exclusive: (work) => work());
    await _refresh();
    return true;
  }

  /// Turns the lock on, for the account whose session is open.
  Future<void> enable(String passphrase) async {
    final uid = _uid, lock = _lock;
    final session = ref.read(appSessionProvider).value;
    if (uid == null || lock == null || session == null) {
      throw StateError('No account is open.');
    }
    await lock.enable(
      uid: uid,
      deviceId: session.device.keys.deviceId,
      passphrase: passphrase,
      exclusive: _exclusive,
    );
    await _refresh();
  }

  Future<void> disable() async {
    final uid = _uid, lock = _lock;
    if (uid == null || lock == null) return;
    await lock.disable(uid, exclusive: _exclusive);
    await _refresh();
  }

  /// False, changing nothing, when [current] is not the passphrase.
  Future<bool> change(String current, String next) async {
    final uid = _uid, lock = _lock;
    if (uid == null || lock == null) return false;
    return lock.change(uid, current, next);
  }

  Future<void> setAutoLock(AutoLock autoLock) async {
    final uid = _uid, lock = _lock;
    if (uid == null || lock == null) return;
    await lock.setAutoLock(uid, autoLock);
    await _refresh();
  }

  /// Closes the account's session, so what it was writing is saved, then
  /// forgets the data key. The app shows the unlock screen.
  Future<void> lockNow() async {
    final current = state.value;
    if (current == null || !current.on || !current.open) return;
    await ref.read(appSessionProvider).value?.close();
    _lock?.lock();
    await _refresh();
  }
}

final passphraseLockProvider =
    AsyncNotifierProvider<PassphraseLockController, LockState>(
      PassphraseLockController.new,
    );

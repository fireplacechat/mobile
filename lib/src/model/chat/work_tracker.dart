import 'dart:async';

/// Tracks receives and sync cancellation without owning the session mutex.
class WorkTracker {
  bool _closed = false;
  Future<void>? _closing;
  Future<void>? _draining;
  final _syncCancels = <Future<void> Function()>{};
  final _receiveWork = <Future<void>>{};

  bool get closed => _closed;
  void markClosed() => _closed = true;

  void track(Future<void> work) {
    final guarded = work.catchError((Object _) {});
    _receiveWork.add(guarded);
    unawaited(guarded.then((_) => _receiveWork.remove(guarded)));
  }

  void addCancel(Future<void> Function() cancel) => _syncCancels.add(cancel);
  void removeCancel(Future<void> Function() cancel) =>
      _syncCancels.remove(cancel);

  /// Memoize the entire service shutdown, including the lock wait and cleanup.
  /// ChatService retains the shutdown ordering inside this callback.
  Future<void> close(Future<void> Function() shutdown) =>
      _closing ??= shutdown();

  Future<void> cancelAndDrain() => _draining ??= () async {
    for (final cancel in _syncCancels.toList()) {
      await cancel();
    }
    while (_receiveWork.isNotEmpty) {
      await Future.wait(_receiveWork.toList());
    }
  }();
}

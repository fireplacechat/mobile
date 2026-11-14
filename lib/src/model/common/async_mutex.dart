import 'dart:async';

/// Runs async actions one at a time, in call order, within one isolate (across
/// isolates, use `SharedLock`). A failed action does not block the next one.
/// An action must not await another run on the same mutex: it would deadlock.
class AsyncMutex {
  Future<void> _last = Future.value();
  Future<T> run<T>(Future<T> Function() f) {
    final c = Completer<T>();
    final prev = _last;
    _last = c.future.then((_) {}, onError: (_) {});
    prev.then((_) async {
      try {
        c.complete(await f());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }
}

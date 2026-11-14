import 'dart:async';

/// Queues asynchronous actions in call order within one isolate.
/// An action's error reaches its caller without blocking later actions.
/// Actions must not await another run on the same mutex.
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

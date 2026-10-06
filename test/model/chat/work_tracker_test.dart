import 'dart:async';

import 'package:fireplace/src/model/chat/work_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('close waits for tracked work and marks closed immediately', () async {
    final tracker = WorkTracker();
    final work = Completer<void>();
    tracker.track(work.future);
    var completed = false;
    final closing = tracker.close(() async {
      tracker.markClosed();
      await tracker.cancelAndDrain();
    });
    unawaited(closing.then((_) => completed = true));
    expect(tracker.closed, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    work.complete();
    await closing;
    expect(completed, isTrue);
  });

  test('close is idempotent through the final shutdown tail', () async {
    final tracker = WorkTracker();
    final tail = Completer<void>();
    var calls = 0;
    Future<void> shutdown() async {
      calls++;
      tracker.markClosed();
      await tracker.cancelAndDrain();
      await tail.future;
    }

    final first = tracker.close(shutdown);
    final second = tracker.close(shutdown);
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    tail.complete();
    await Future.wait([first, second]);
    expect(identical(tracker.close(shutdown), first), isTrue);
    expect(calls, 1);
  });

  test('each registered cancel runs once in registration order', () async {
    final tracker = WorkTracker();
    final calls = <String>[];
    Future<void> first() async => calls.add('first');
    Future<void> second() async => calls.add('second');
    tracker.addCancel(first);
    tracker.addCancel(first);
    tracker.addCancel(second);
    await Future.wait([tracker.cancelAndDrain(), tracker.cancelAndDrain()]);
    expect(calls, ['first', 'second']);
  });

  test('removed sync cancels are not called during shutdown', () async {
    final tracker = WorkTracker();
    var calls = 0;
    Future<void> cancel() async => calls++;
    tracker.addCancel(cancel);
    tracker.removeCancel(cancel);
    await tracker.cancelAndDrain();
    expect(calls, 0);
  });

  test('tracked failures are consumed without leaking an error', () async {
    final tracker = WorkTracker();
    final work = Completer<void>();
    tracker.track(work.future);
    work.completeError(StateError('receive failed'));
    await tracker.cancelAndDrain();
    await Future<void>.delayed(Duration.zero);
  });

  test('drain also waits for work added while closing', () async {
    final tracker = WorkTracker();
    final first = Completer<void>();
    final added = Completer<void>();
    tracker.track(first.future);
    var done = false;
    final drain = tracker.cancelAndDrain();
    unawaited(drain.then((_) => done = true));
    tracker.track(added.future);
    first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    added.complete();
    await drain;
    expect(done, isTrue);
  });
}

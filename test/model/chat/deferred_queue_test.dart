import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fireplace/src/model/chat/deferred_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cursor is bounded by the oldest unfinished timestamp for its chat', () {
    final queue = DeferredQueue();
    queue.registerUnfinished('a', 'later', Timestamp(20, 0));
    queue.registerUnfinished('a', 'earliest', Timestamp(10, 1));
    queue.registerUnfinished('a', 'same-second', Timestamp(10, 2));
    queue.registerUnfinished('b', 'other', Timestamp(1, 0));
    expect(queue.clampCursor('a', Timestamp(30, 0)), Timestamp(10, 1));
    expect(queue.clampCursor('a', Timestamp(5, 0)), Timestamp(5, 0));
    expect(queue.clampCursor('missing', Timestamp(30, 0)), Timestamp(30, 0));
  });

  test('a null unfinished timestamp blocks only its own chat', () {
    final queue = DeferredQueue();
    queue.registerUnfinished('a', 'unknown', null);
    queue.registerUnfinished('b', 'known', Timestamp(10, 0));
    expect(queue.clampCursor('a', Timestamp(30, 0)), isNull);
    expect(queue.clampCursor('b', Timestamp(30, 0)), Timestamp(10, 0));
    expect(queue.clampCursor('b', null), isNull);
  });

  test('completion removes retry work and releases its cursor boundary', () {
    final queue = DeferredQueue();
    queue.defer('a', 'm', {'value': 1});
    final snapshot = queue.pending;
    queue.defer('a', 'm', {'value': 2});
    queue.registerUnfinished('a', 'm', null);
    expect(queue.pending.single.data, {'value': 2});
    expect(snapshot.single.data, {'value': 1});
    queue.complete('a', 'm');
    expect(queue.pending, isEmpty);
    expect(queue.clampCursor('a', Timestamp(10, 0)), Timestamp(10, 0));
  });

  testWidgets('retry is scheduled once and cleared before its callback', (
    tester,
  ) async {
    final queue = DeferredQueue();
    var first = 0;
    var second = 0;
    queue.scheduleRetry(() {
      first++;
      expectSync(queue.retryScheduled, isFalse);
      queue.scheduleRetry(() => second++);
    });
    queue.scheduleRetry(() => second += 100);
    expect(queue.retryScheduled, isTrue);
    await tester.pump(const Duration(seconds: 65));
    expect(first, 1);
    expect(second, 0);
    expect(queue.retryScheduled, isTrue);
    await tester.pump(const Duration(seconds: 65));
    expect(second, 1);
    expect(queue.retryScheduled, isFalse);
    queue.close();
  });

  testWidgets('close cancels retry without clearing work before the lock', (
    tester,
  ) async {
    final queue = DeferredQueue();
    var calls = 0;
    queue.defer('a', 'm', {});
    queue.registerUnfinished('a', 'm', null);
    queue.scheduleRetry(() => calls++);
    queue.close();
    queue.close();
    expect(queue.retryScheduled, isFalse);
    await tester.pump(const Duration(seconds: 130));
    expect(calls, 0);
    expect(queue.pending, hasLength(1));
    expect(queue.clampCursor('a', Timestamp(20, 0)), isNull);
    queue.clearDeferred();
    queue.clearUnfinished();
    expect(queue.pending, isEmpty);
    expect(queue.clampCursor('a', Timestamp(20, 0)), Timestamp(20, 0));
  });
}

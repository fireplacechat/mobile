import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/src/model/common/async_mutex.dart';

// Issue #17: sending, receiving and shutdown take turns through AsyncMutex.

void main() {
  test('jobs run one at a time, in the order they were started', () async {
    final mutex = AsyncMutex();
    final first = Completer<void>();
    final log = <String>[];
    final a = mutex.run(() async {
      log.add('a start');
      await first.future;
      log.add('a end');
    });
    final b = mutex.run(() async => log.add('b'));
    final c = mutex.run(() async => log.add('c'));
    await pumpEventQueue();
    expect(log, ['a start'], reason: 'b waits while a is held open');
    first.complete();
    await Future.wait([a, b, c]);
    expect(log, ['a start', 'a end', 'b', 'c']);
  });

  test('run returns the job value', () async {
    final mutex = AsyncMutex();
    expect(await mutex.run(() async => 42), 42);
    expect(await mutex.run(() async => 'text'), 'text');
  });

  test('a failing job gives its error to its caller only', () async {
    final mutex = AsyncMutex();
    final failing = mutex.run<int>(() async => throw StateError('boom'));
    final next = mutex.run(() async => 'next ran');
    await expectLater(failing, throwsA(isA<StateError>()));
    expect(await next, 'next ran');
  });

  test('a synchronous throw is also delivered as an error', () async {
    final mutex = AsyncMutex();
    await expectLater(
      mutex.run<void>(() => throw ArgumentError('sync')),
      throwsA(isA<ArgumentError>()),
    );
    expect(await mutex.run(() async => 1), 1);
  });

  test('many jobs started at once never overlap', () async {
    final mutex = AsyncMutex();
    var running = 0, most = 0;
    final order = <int>[];
    await Future.wait([
      for (var i = 0; i < 50; i++)
        mutex.run(() async {
          running++;
          most = running > most ? running : most;
          await Future<void>.delayed(Duration.zero);
          order.add(i);
          running--;
        }),
    ]);
    expect(most, 1);
    expect(order, List.generate(50, (i) => i));
  });
}

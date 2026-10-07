import 'dart:async';

import 'package:fireplace/src/model/common/session_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cleanup runs cleaners in reverse and returns the same future',
    () async {
      final scope = SessionScope(isMounted: () => true);
      final calls = <int>[];
      final gate = Completer<void>();
      scope.add(() async => calls.add(1));
      scope.add(() async {
        calls.add(2);
        await gate.future;
      });
      final first = scope.cleanup();
      expect(scope.stopped, isTrue);
      expect(scope.cleanup(), same(first));
      expect(calls, [2]);
      gate.complete();
      await first;
      await scope.cleanup();
      expect(calls, [2, 1]);
    },
  );

  test('cleanup runs all cleaners and rethrows the first error', () async {
    final scope = SessionScope(isMounted: () => true);
    final calls = <int>[];
    final first = StateError('first');
    scope.add(() async => calls.add(1));
    scope.add(() async {
      calls.add(2);
      throw StateError('second');
    });
    scope.add(() async {
      calls.add(3);
      throw first;
    });
    await expectLater(scope.cleanup(), throwsA(same(first)));
    expect(calls, [3, 2, 1]);
  });

  for (final reason in ['cleanup', 'dispose', 'unmounted']) {
    test('checkActive refuses work after $reason', () async {
      var mounted = true;
      final scope = SessionScope(isMounted: () => mounted);
      scope.checkActive();
      if (reason == 'cleanup') await scope.cleanup();
      if (reason == 'dispose') scope.disposed();
      if (reason == 'unmounted') mounted = false;
      expect(
        scope.checkActive,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Session initialization cancelled.',
          ),
        ),
      );
    });
  }

  test('disposal during startup defers cleanup until finish', () async {
    final scope = SessionScope(isMounted: () => true);
    var calls = 0;
    scope.add(() async => calls++);
    scope.disposed();
    expect(scope.stopped, isTrue);
    expect(calls, 0);
    scope.succeeded();
    await scope.finish();
    await scope.cleanup();
    expect(calls, 1);
  });

  test('unsuccessful finish cleans up', () async {
    final scope = SessionScope(isMounted: () => true);
    var calls = 0;
    scope.add(() async => calls++);
    await scope.finish();
    expect(calls, 1);
    expect(scope.stopped, isTrue);
  });

  test('successful finish leaves resources active until disposal', () async {
    final scope = SessionScope(isMounted: () => true);
    var calls = 0;
    scope.add(() async => calls++);
    scope.succeeded();
    await scope.finish();
    expect(calls, 0);
    expect(scope.stopped, isFalse);
    scope.disposed();
    await scope.cleanup();
    expect(calls, 1);
  });

  test('disposal after successful finish swallows cleanup errors', () async {
    final scope = SessionScope(isMounted: () => true);
    final ran = Completer<void>();
    scope.add(() async {
      ran.complete();
      throw StateError('cleanup');
    });
    scope.succeeded();
    await scope.finish();
    scope.disposed();
    await ran.future;
    await Future<void>.delayed(Duration.zero);
    expect(scope.stopped, isTrue);
  });
}

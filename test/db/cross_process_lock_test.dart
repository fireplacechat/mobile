import 'dart:async';
import 'dart:io';

import 'package:fireplace/src/db/shared_lock.dart';
import 'package:flutter_test/flutter_test.dart';

// An independent process checks the OS lock, using the Python already used by
// this repository's checks. In particular this verifies POSIX fcntl semantics.
const _probe = '''
import os,sys
f=open(sys.argv[1], 'r+b')
try:
    if os.name == 'nt':
        import msvcrt
        msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
    else:
        import fcntl
        fcntl.lockf(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    print('acquired')
except (BlockingIOError, OSError):
    print('blocked')
finally:
    f.close()
''';

Future<String> _probeLock(File file) async {
  final result = await Process.run(Platform.isWindows ? 'python' : 'python3', [
    '-c',
    _probe,
    file.path,
  ]).timeout(const Duration(seconds: 10));
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return (result.stdout as String).trim();
}

void main() {
  test(
    'an independent process is excluded, including an exceptional hold',
    () async {
      final dir = await Directory.systemTemp.createTemp('fireplace-lock-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/account.lock');
      await file.writeAsBytes([0]);
      final hub = MemoryLockHub();
      final lock = SharedLock(
        gate: CrossProcessLockGate(file, isolateGate: MemoryLockGate(hub)),
      );
      addTearDown(lock.close);
      expect(await _probeLock(file), 'acquired');
      await expectLater(
        lock.run(() async {
          expect(await _probeLock(file), 'blocked');
          throw StateError('fictional failure');
        }),
        throwsStateError,
      );
      expect(await _probeLock(file), 'acquired');
      await lock.run(() async => expect(await _probeLock(file), 'blocked'));
      expect(await _probeLock(file), 'acquired');
    },
  );

  test('close waits for the active action and rejects later callers', () async {
    final entered = Completer<void>(), finish = Completer<void>();
    final lock = SharedLock();
    final hold = lock.run(() async {
      entered.complete();
      await finish.future;
      // Re-entrant work remains part of the active hold during shutdown.
      return lock.run(() async => 7);
    });
    await entered.future;
    final closing = lock.close();
    await expectLater(lock.run(() async => 0), throwsStateError);
    finish.complete();
    expect(await hold, 7);
    await closing;
    await lock.close();
  });
}

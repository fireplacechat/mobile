import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/src/db/shared_lock.dart';

// The account lock between the app and the background push handler
// (decision 0030).

SharedLock _onHub(MemoryLockHub hub) =>
    SharedLock(gate: MemoryLockGate(hub), generation: hub.generation);

/// A second isolate that takes the gate named [name], says so, and lets go
/// when told. With `die`, it exits holding the gate.
Future<void> _holder(List<Object> args) async {
  final name = args[0] as String;
  final out = args[1] as SendPort;
  final die = args[2] as bool;
  final gate = IsolateLockGate(name);
  await gate.acquire();
  final commands = ReceivePort();
  out.send(commands.sendPort);
  if (die) Isolate.exit();
  await commands.first;
  out.send('releasing');
  gate.close();
  commands.close();
}

void main() {
  group('within one isolate', () {
    test('callers take turns in order and get their results', () async {
      final lock = SharedLock();
      final open = Completer<void>();
      final log = <String>[];
      final a = lock.run(() async {
        log.add('a');
        await open.future;
        return 1;
      });
      final b = lock.run(() async {
        log.add('b');
        return 2;
      });
      await pumpEventQueue();
      expect(log, ['a']);
      open.complete();
      expect(await Future.wait([a, b]), [1, 2]);
      expect(log, ['a', 'b']);
    });

    test('an error reaches its caller and the lock is free again', () async {
      final lock = SharedLock();
      await expectLater(
        lock.run<void>(() async => throw StateError('x')),
        throwsStateError,
      );
      expect(await lock.run(() async => 'free'), 'free');
    });

    test('is re-entrant within one call chain', () async {
      final lock = SharedLock();
      final result = await lock.run(
        () => lock.run(() => lock.run(() async => 'nested')),
      );
      expect(result, 'nested');
    });

    test('work that outlives its hold waits its turn again', () async {
      final lock = SharedLock();
      final log = <String>[];
      late Future<void> escaped;
      final open = Completer<void>();
      await lock.run(() async {
        // Started while holding, but not waited for.
        escaped = Future<void>.delayed(const Duration(milliseconds: 1))
            .then((_) => lock.run(() async => log.add('escaped')));
      });
      final next = lock.run(() async {
        log.add('next start');
        await open.future;
        log.add('next end');
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(log, ['next start'], reason: 'the hold ended, so it waits');
      open.complete();
      await Future.wait([escaped, next]);
      expect(log, ['next start', 'next end', 'escaped']);
    });
  });

  group('between isolates', () {
    test('two locks on one gate exclude each other', () async {
      final hub = MemoryLockHub();
      final app = _onHub(hub), background = _onHub(hub);
      var inside = 0, most = 0;
      Future<void> work(SharedLock lock) => lock.run(() async {
        inside++;
        most = inside > most ? inside : most;
        await Future<void>.delayed(Duration.zero);
        inside--;
      });
      await Future.wait([
        for (var i = 0; i < 20; i++) work(i.isEven ? app : background),
      ]);
      expect(most, 1);
    });

    test('caches are dropped only when the other one held the lock', () async {
      final hub = MemoryLockHub();
      final app = _onHub(hub), background = _onHub(hub);
      var drops = 0;
      app.onInvalidate(() => drops++);
      await app.run(() async {});
      expect(drops, 1, reason: 'nothing is known before the first hold');
      await app.run(() async {});
      await app.run(() async {});
      expect(drops, 1, reason: 'only this isolate wrote');
      await background.run(() async {});
      await app.run(() async {});
      expect(drops, 2, reason: 'the background isolate wrote meanwhile');
      await app.run(() => app.run(() async {}));
      expect(drops, 2);
    });

    test('caches are dropped before the caller runs', () async {
      final hub = MemoryLockHub();
      final app = _onHub(hub), background = _onHub(hub);
      final log = <String>[];
      app.onInvalidate(() async {
        await Future<void>.delayed(Duration.zero);
        log.add('dropped');
      });
      await app.run(() async {});
      await background.run(() async {});
      log.clear();
      await app.run(() async => log.add('ran'));
      expect(log, ['dropped', 'ran']);
    });

    test('the generation file tells two locks apart', () async {
      final dir = await Directory.systemTemp.createTemp('lockgen');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/lock.gen');
      final a = SharedLock(generation: FileLockGeneration(file));
      final b = SharedLock(generation: FileLockGeneration(file));
      var drops = 0;
      a.onInvalidate(() => drops++);
      await a.run(() async {});
      await a.run(() async {});
      expect(drops, 1);
      await b.run(() async {});
      await a.run(() async {});
      expect(drops, 2);
      // An unreadable file counts as a change.
      await file.writeAsString('garbage');
      await a.run(() async {});
      expect(drops, 3);
    });

    test('the isolate gate excludes a holder in another isolate', () async {
      const name = 'fireplace.test.held';
      addTearDown(() => IsolateNameServer.removePortNameMapping(name));
      final events = ReceivePort();
      final messages = StreamIterator(events);
      await Isolate.spawn(_holder, [name, events.sendPort, false]);
      expect(await messages.moveNext(), isTrue);
      final release = messages.current as SendPort;
      final gate = IsolateLockGate(name);
      addTearDown(gate.close);
      var acquired = false;
      final waiting = gate.acquire().then((_) => acquired = true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(acquired, isFalse, reason: 'the other isolate holds it');
      release.send('go');
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, 'releasing');
      await waiting;
      expect(acquired, isTrue);
      gate.release();
      expect(IsolateNameServer.lookupPortByName(name), isNull);
      await messages.cancel();
    });

    test('a holder whose isolate died is reclaimed', () async {
      const name = 'fireplace.test.dead';
      addTearDown(() => IsolateNameServer.removePortNameMapping(name));
      final events = ReceivePort();
      final exited = ReceivePort();
      await Isolate.spawn(_holder, [
        name,
        events.sendPort,
        true,
      ], onExit: exited.sendPort);
      await exited.first;
      events.close();
      expect(IsolateNameServer.lookupPortByName(name), isNotNull);
      final gate = IsolateLockGate(
        name,
        pingTimeout: const Duration(milliseconds: 50),
        pingEvery: Duration.zero,
      );
      addTearDown(gate.close);
      await gate.acquire().timeout(const Duration(seconds: 10));
      gate.release();
    });
  });
}

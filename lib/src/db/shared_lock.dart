// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

/// The account lock (decision 0030): one at a time, the app's isolate or the
/// background isolate that handles a push changes sessions, the receive
/// journal, history and the private prekeys.
///
/// - Within an isolate, callers take turns in the order they asked.
/// - Between isolates, a [LockGate] makes the holder the only one.
/// - A [LockGeneration] tells the next holder whether another isolate held it
///   since this one did. If so, everything registered with [onInvalidate]
///   (memory caches) is dropped before the caller runs.
///
/// It is re-entrant within one call chain: code that holds it (a receive) may
/// call code that takes it again (saving history, consuming a prekey). Work
/// that a holder starts but does not wait for may outlive the hold; once the
/// hold ends it takes the lock again like anyone else.
class SharedLock {
  SharedLock({LockGate? gate, LockGeneration? generation})
    : _gate = gate,
      _generation = generation;

  final LockGate? _gate;
  final LockGeneration? _generation;
  final _local = _Turns();
  final _zoneKey = Object();
  final _invalidators = <FutureOr<void> Function()>[];
  Future<void>? _closing;

  /// The generation this isolate last wrote, or null before it held the lock.
  int? _seen;

  /// Runs [action] while holding the lock.
  Future<T> run<T>(Future<T> Function() action) {
    final hold = Zone.current[_zoneKey];
    if (hold is _Hold && hold.active) return action();
    if (_closing != null) return Future.error(StateError('Lock closed.'));
    return _local.run(() async {
      await _gate?.acquire();
      final hold = _Hold();
      try {
        await _catchUp();
        return await runZoned(action, zoneValues: {_zoneKey: hold});
      } finally {
        hold.active = false;
        try {
          await _advance();
        } finally {
          await _gate?.release();
        }
      }
    });
  }

  /// Registers a cache to drop when another isolate held the lock meanwhile.
  void onInvalidate(FutureOr<void> Function() drop) => _invalidators.add(drop);

  Future<void> _catchUp() async {
    final generation = _generation;
    if (generation == null) return;
    int? now;
    try {
      now = await generation.read();
    } catch (_) {
      now = null; // unreadable: assume someone else wrote
    }
    if (now != null && now == _seen) return;
    _seen = now;
    for (final drop in List.of(_invalidators)) {
      await drop();
    }
  }

  Future<void> _advance() async {
    final generation = _generation;
    if (generation == null) return;
    final next = (_seen ?? 0) + 1;
    try {
      await generation.write(next);
      _seen = next;
    } catch (_) {
      // Next time this isolate drops its own caches too. The other side
      // cannot be told; the file sits next to history, so if it cannot be
      // written, history cannot be either.
      _seen = null;
    }
  }

  /// Waits for queued holders, then releases the gate's open resources.
  Future<void> close() => _closing ??= _local.run(() async {
    await _gate?.close();
  });
}

class _Hold {
  bool active = true;
}

/// First come, first served, within one isolate. The same as the model's
/// `AsyncMutex`, which this layer may not import.
class _Turns {
  Future<void> _last = Future.value();
  Future<T> run<T>(Future<T> Function() f) {
    final done = Completer<T>();
    final previous = _last;
    _last = done.future.then((_) {}, onError: (_) {});
    previous.then((_) async {
      try {
        done.complete(await f());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }
}

/// Makes one lock holder at a time across isolates (or processes).
abstract interface class LockGate {
  /// Waits until this caller holds the gate.
  Future<void> acquire();

  /// Lets the next caller in. Only called by the holder.
  FutureOr<void> release();

  FutureOr<void> close();
}

/// Adds a process-wide file lock outside the isolate gate. POSIX locks alone
/// cannot exclude two isolates in the same process. Keep the isolate gate
/// held until the file descriptor is closed: closing any descriptor for this
/// file releases that process's POSIX locks. Swift must use fcntl, not flock.
class CrossProcessLockGate implements LockGate {
  CrossProcessLockGate(this.file, {required LockGate isolateGate})
    : _isolateGate = isolateGate;

  final File file;
  final LockGate _isolateGate;
  RandomAccessFile? _held;
  bool _closed = false;

  @override
  Future<void> acquire() async {
    if (_closed) throw StateError('Lock closed.');
    await _isolateGate.acquire();
    RandomAccessFile? opened;
    try {
      await file.parent.create(recursive: true);
      opened = await file.open(mode: FileMode.append);
      await opened.lock(FileLock.blockingExclusive);
      _held = opened;
    } catch (_) {
      try {
        await opened?.close();
      } finally {
        await _isolateGate.release();
      }
      rethrow;
    }
  }

  @override
  Future<void> release() async {
    final opened = _held;
    _held = null;
    if (opened == null) return;
    try {
      // Closing also releases the OS lock, including when an action threw.
      await opened.close();
    } finally {
      await _isolateGate.release();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await release();
    } finally {
      await _isolateGate.close();
    }
  }
}

/// A number that every lock holder raises by one as it lets go.
abstract interface class LockGeneration {
  Future<int?> read();
  Future<void> write(int value);
}

/// The generation in a small file next to the history it protects.
class FileLockGeneration implements LockGeneration {
  FileLockGeneration(this.file);
  final File file;

  @override
  Future<int?> read() async {
    if (!await file.exists()) return 0;
    return int.tryParse((await file.readAsString()).trim());
  }

  // Not flushed: after a crash every cache is gone anyway, so only isolates
  // that are alive at the same time need to agree.
  @override
  Future<void> write(int value) => file.writeAsString('$value');
}

/// Between isolates of one process, through `IsolateNameServer`: registering
/// a port under [name] is an atomic test-and-set, and removing the name lets
/// the next one in. POSIX file locks cannot do this: they belong to the
/// process, so two isolates would both get them.
///
/// A holder whose isolate died (its Flutter engine was destroyed) leaves its
/// name behind. A waiter pings the holder; one that does not answer
/// [missedPings] times in a row, each within [pingTimeout], is gone, and its
/// name is removed. A live isolate answers even while it awaits the network.
class IsolateLockGate implements LockGate {
  IsolateLockGate(
    this.name, {
    this.pingTimeout = const Duration(seconds: 2),
    this.pingEvery = const Duration(milliseconds: 500),
    this.missedPings = 2,
  }) {
    _port.listen((message) {
      if (message is SendPort) message.send(true);
    });
  }

  final String name;
  final Duration pingTimeout;
  final Duration pingEvery;
  final int missedPings;
  final _port = ReceivePort();
  var _closed = false;

  @override
  Future<void> acquire() async {
    if (_closed) throw StateError('Lock closed.');
    var wait = const Duration(milliseconds: 2);
    var lastPing = DateTime.now();
    SendPort? suspect;
    var misses = 0;
    while (true) {
      if (IsolateNameServer.registerPortWithName(_port.sendPort, name)) return;
      final holder = IsolateNameServer.lookupPortByName(name);
      if (holder == null) continue; // let go just now: try again at once
      if (DateTime.now().difference(lastPing) >= pingEvery) {
        final alive = await _answers(holder);
        lastPing = DateTime.now();
        if (alive) {
          misses = 0;
        } else {
          misses = holder == suspect ? misses + 1 : 1;
          suspect = holder;
          if (misses >= missedPings &&
              IsolateNameServer.lookupPortByName(name) == holder) {
            IsolateNameServer.removePortNameMapping(name);
            misses = 0;
            continue;
          }
        }
      }
      await Future<void>.delayed(wait);
      if (wait < const Duration(milliseconds: 50)) wait *= 2;
    }
  }

  Future<bool> _answers(SendPort holder) async {
    final reply = ReceivePort();
    try {
      holder.send(reply.sendPort);
      await reply.first.timeout(pingTimeout);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      reply.close();
    }
  }

  @override
  void release() {
    if (IsolateNameServer.lookupPortByName(name) == _port.sendPort) {
      IsolateNameServer.removePortNameMapping(name);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    release();
    _port.close();
  }
}

/// For tests: gates sharing one [MemoryLockHub] exclude each other, like
/// isolates sharing a name server.
class MemoryLockHub {
  final _gate = _Turns();
  final generation = MemoryLockGeneration();
}

class MemoryLockGate implements LockGate {
  MemoryLockGate(this.hub);
  final MemoryLockHub hub;
  Completer<void>? _held;

  @override
  Future<void> acquire() {
    final entered = Completer<void>();
    final held = Completer<void>();
    unawaited(
      hub._gate.run(() {
        _held = held;
        entered.complete();
        return held.future;
      }),
    );
    return entered.future;
  }

  @override
  void release() {
    _held?.complete();
    _held = null;
  }

  @override
  void close() => release();
}

class MemoryLockGeneration implements LockGeneration {
  int value = 0;
  @override
  Future<int?> read() async => value;
  @override
  Future<void> write(int value) async => this.value = value;
}

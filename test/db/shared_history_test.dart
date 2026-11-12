import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/src/db/encrypted_message_store.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/shared_lock.dart';

// The app and the background push handler open the same history, each with
// its own memory cache (decision 0030).

const _chat = 'alice_bob';

LocalMessage _m(int i) => LocalMessage(
  id: 'm$i',
  chatId: _chat,
  senderUid: 'bob',
  senderDevice: 'bob-device',
  outgoing: false,
  sentAt: DateTime.utc(2026, 11, 12).add(Duration(seconds: i)),
  body: 'message $i',
);

class _SlowReads extends MemorySecretStore {
  Completer<void>? hold;
  @override
  Future<String?> read(String key) async {
    final value = data[key];
    await hold?.future;
    return value;
  }
}

void main() {
  late Directory dir;
  late MemorySecretStore secrets;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shared_history');
    secrets = MemorySecretStore();
  });
  tearDown(() => dir.delete(recursive: true));

  Future<EncryptedFileMessageStore> open(SharedLock lock) =>
      EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
        lock: lock,
      );

  Future<List<String>> onDisk() async {
    final fresh = await open(SharedLock());
    return [for (final m in await fresh.watch(_chat).first) m.id];
  }

  test('a message saved by the other isolate is not overwritten', () async {
    final hub = MemoryLockHub();
    final app = await open(
      SharedLock(gate: MemoryLockGate(hub), generation: hub.generation),
    );
    final background = await open(
      SharedLock(gate: MemoryLockGate(hub), generation: hub.generation),
    );
    await app.add(_m(1));
    expect(await background.has(_chat, 'm1'), isTrue); // cached now
    await app.add(_m(2));
    await background.add(_m(3));
    await app.add(_m(4));
    expect(await onDisk(), ['m1', 'm2', 'm3', 'm4']);
  });

  test('without the shared lock the same writes lose a message', () async {
    // What the lock prevents: each instance trusts its own cache.
    final app = await open(SharedLock());
    final background = await open(SharedLock());
    await app.add(_m(1));
    await background.has(_chat, 'm1');
    await app.add(_m(2));
    await background.add(_m(3));
    expect(await onDisk(), isNot(contains('m2')));
  });

  test('appending to a long chat after the other isolate appended', () async {
    final hub = MemoryLockHub();
    final app = await open(
      SharedLock(gate: MemoryLockGate(hub), generation: hub.generation),
    );
    final count = EncryptedFileMessageStore.appendFrom + 5;
    for (var i = 0; i < count; i++) {
      await app.add(_m(i));
    }
    final background = await open(
      SharedLock(gate: MemoryLockGate(hub), generation: hub.generation),
    );
    expect(await background.has(_chat, 'm0'), isTrue);
    // Both append log entries; the background's view of the log is stale.
    await app.add(_m(count));
    await background.add(_m(count + 1));
    await app.add(_m(count + 2));
    final ids = await onDisk();
    expect(ids.length, count + 3);
    expect(ids.last, 'm${count + 2}');
  });

  test('an open chat shows what the other isolate saved', () async {
    final hub = MemoryLockHub();
    final appLock = SharedLock(
      gate: MemoryLockGate(hub),
      generation: hub.generation,
    );
    final app = await open(appLock);
    final background = await open(
      SharedLock(gate: MemoryLockGate(hub), generation: hub.generation),
    );
    await app.add(_m(1));
    final seen = <List<String>>[];
    final sub = app
        .watch(_chat)
        .listen((l) => seen.add([for (final m in l) m.id]));
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await background.add(_m(2));
    // The app notices when it next takes the lock (its next receive or send).
    await appLock.run(() async {});
    await pumpEventQueue();
    expect(seen.last, ['m1', 'm2']);
  });

  test('the push handler never makes a history key', () async {
    await expectLater(
      EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
        createKey: false,
      ),
      throwsStateError,
    );
    expect(await secrets.read('msgkey:alice'), isNull);
    await open(SharedLock()); // the app makes it
    final background = await EncryptedFileMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
      createKey: false,
    );
    await background.add(_m(1));
    expect(await onDisk(), ['m1']);
  });

  group('CachedSecretStore.forget', () {
    test('reads go to the store again', () async {
      final store = MemorySecretStore();
      final cached = CachedSecretStore(store);
      await cached.write('sess', 'old');
      store.data['sess'] = 'new'; // written by the other isolate
      expect(await cached.read('sess'), 'old');
      cached.forget();
      expect(await cached.read('sess'), 'new');
    });

    test('a read under way when it is called is not remembered', () async {
      final store = _SlowReads()..data['sess'] = 'old';
      final cached = CachedSecretStore(store);
      store.hold = Completer<void>();
      final reading = cached.read('sess');
      await pumpEventQueue();
      store.data['sess'] = 'new';
      cached.forget();
      store.hold!.complete();
      expect(await reading, 'old');
      store.hold = null;
      expect(await cached.read('sess'), 'new');
    });
  });
}

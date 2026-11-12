import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'durability_test.dart' show Phone, eventually;

/// Counts every call that would be a platform (Keychain) round trip.
class _CountingStore extends MemorySecretStore {
  int calls = 0;
  @override
  Future<String?> read(String key) {
    calls++;
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) {
    calls++;
    return super.write(key, value);
  }

  @override
  Future<void> delete(String key) {
    calls++;
    return super.delete(key);
  }
}

/// A store whose next read waits until released.
class _SlowReadStore extends MemorySecretStore {
  Completer<void>? hold;
  @override
  Future<String?> read(String key) async {
    final value = data[key];
    await hold?.future;
    return value;
  }
}

void main() {
  group('CachedSecretStore', () {
    test('reads a key from the store once', () async {
      final store = _CountingStore()..data['k'] = 'v';
      final cached = CachedSecretStore(store);
      for (var i = 0; i < 3; i++) {
        expect(await cached.read('k'), 'v');
      }
      expect(await cached.read('missing'), isNull);
      expect(await cached.read('missing'), isNull);
      expect(store.calls, 2);
    });

    test('a write goes to the store and is remembered', () async {
      final store = _CountingStore();
      final cached = CachedSecretStore(store);
      await cached.write('k', 'v');
      expect(store.data['k'], 'v');
      expect(await cached.read('k'), 'v');
      await cached.delete('k');
      expect(store.data.containsKey('k'), isFalse);
      expect(await cached.read('k'), isNull);
      expect(store.calls, 2, reason: 'only the write and the delete');
    });

    test('a failed write forgets the key', () async {
      final store = _FailingStore()..data['k'] = 'old';
      final cached = CachedSecretStore(store);
      expect(await cached.read('k'), 'old');
      store.fail = true;
      await expectLater(cached.write('k', 'new'), throwsA(isA<StateError>()));
      store.fail = false;
      store.data['k'] = 'what the store holds';
      expect(await cached.read('k'), 'what the store holds');
    });

    test('a read that overlapped a write is not remembered', () async {
      final store = _SlowReadStore()..data['k'] = 'old';
      final cached = CachedSecretStore(store);
      store.hold = Completer<void>();
      final reading = cached.read('k');
      await cached.write('k', 'new');
      store.hold!.complete();
      expect(await reading, 'old');
      expect(await cached.read('k'), 'new');
    });
  });

  test('receiving a message takes a handful of Keychain calls', () async {
    final db = FakeFirebaseFirestore();
    for (final u in ['alice', 'bob']) {
      await db.collection('usernames').doc(u).set({'uid': u});
      await db.collection('users').doc(u).set({'username': u});
    }
    final alice = await Phone.create(db, 'alice');
    final store = _CountingStore();
    final bob = await Phone.create(db, 'bob');
    // Bob's chat service over a counting copy of his keys.
    store.data.addAll(bob.secrets.data);
    final chat = ChatService(
      db: db,
      uid: 'bob',
      device: bob.device,
      keys: bob.keys,
      prekeys: bob.prekeys,
      secrets: store,
      messages: bob.messages,
    );
    addTearDown(chat.close);
    await alice.chat.startChat('bob');
    await chat.acceptRequest('alice_bob');
    final sub = chat.startSync('alice_bob');
    addTearDown(sub.cancel);
    await alice.chat.sendText('alice_bob', 'first');
    await eventually(
      () async => (await bob.bodies('alice_bob')).length == 1,
      'first',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    store.calls = 0;
    await alice.chat.sendText('alice_bob', 'second');
    await eventually(
      () async => (await bob.bodies('alice_bob')).length == 2,
      'second',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Journal written and closed, session saved, read position saved. It
    // was about eleven before (journal index, repeated reads).
    expect(store.calls, lessThanOrEqualTo(4));
  });

  test('a journal left by an older version is still finished', () async {
    final db = FakeFirebaseFirestore();
    for (final u in ['alice', 'bob']) {
      await db.collection('usernames').doc(u).set({'uid': u});
      await db.collection('users').doc(u).set({'username': u});
    }
    final alice = await Phone.create(db, 'alice');
    final bob = await Phone.create(db, 'bob');
    await alice.chat.startChat('bob');
    await bob.chat.acceptRequest('alice_bob');
    await alice.chat.sendText('alice_bob', 'm1');
    // The session save keeps failing: the journal stays open with the
    // history already written.
    bob.secrets.failNext('sess:', 99);
    bob.sub = bob.chat.startSync('alice_bob');
    await eventually(
      () async =>
          bob.secrets.data.containsKey('journal:${bob.device.keys.deviceId}'),
      'journal open',
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await bob.sub?.cancel();
    // Rewrite it the way older versions stored it: one key per message and
    // an index.
    final slot = 'journal:${bob.device.keys.deviceId}';
    final legacy = '$slot:alice_bob:m1';
    bob.secrets.data[legacy] = bob.secrets.data.remove(slot)!;
    bob.secrets.data['journals:${bob.device.keys.deviceId}'] = '["$legacy"]';

    bob.secrets.times = 0;
    bob.restart();
    await alice.chat.sendText('alice_bob', 'm2');
    bob.sub = bob.chat.startSync('alice_bob');
    await eventually(
      () async => (await bob.bodies('alice_bob')).contains('m2'),
      'the next message decrypts after the old journal is finished',
    );
    expect(
      bob.secrets.data.keys.where((k) => k.startsWith('journal')),
      isEmpty,
    );
    await bob.sub?.cancel();
  });
}

class _FailingStore extends MemorySecretStore {
  bool fail = false;
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('store unavailable');
    await super.write(key, value);
  }
}

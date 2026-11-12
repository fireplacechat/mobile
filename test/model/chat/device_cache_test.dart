import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/chat/device_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_linked_device_test.dart' show Dev, addUser, eventually;

/// Controls the listener by hand and counts direct reads.
class _Keys extends Fake implements KeyService {
  final watches = <String, StreamController<List<DeviceBundle>>>{};
  final fetched = <String>[];
  Object? fetchError;

  @override
  Stream<List<DeviceBundle>> watchDevices(String uid) =>
      (watches[uid] = StreamController<List<DeviceBundle>>()).stream;

  @override
  Future<List<DeviceBundle>> fetchDevices(String uid) async {
    fetched.add(uid);
    if (fetchError != null) throw fetchError!;
    return const [];
  }
}

/// A real key service that counts direct device-list reads.
class _CountingKeys extends KeyService {
  _CountingKeys(super.db, super.store);
  int fetches = 0;
  @override
  Future<List<DeviceBundle>> fetchDevices(String uid) {
    fetches++;
    return super.fetchDevices(uid);
  }
}

void main() {
  test('a known list is used without reading it again', () async {
    final keys = _Keys();
    final cache = DeviceCache(keys);
    addTearDown(cache.close);
    cache.warm('bob');
    keys.watches['bob']!.add(const []);
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 3; i++) {
      expect(await cache.devices('bob'), isEmpty);
    }
    expect(keys.fetched, isEmpty);
  });

  test('a listener that has not answered yet falls back to a read', () async {
    final keys = _Keys();
    final cache = DeviceCache(
      keys,
      firstWait: const Duration(milliseconds: 20),
    );
    addTearDown(cache.close);
    expect(await cache.devices('bob'), isEmpty);
    expect(keys.fetched, ['bob']);
  });

  test('a changed identity is checked again on every send', () async {
    final keys = _Keys()
      ..fetchError = IdentityChangedException('bob', List.filled(64, 1));
    final cache = DeviceCache(keys);
    addTearDown(cache.close);
    cache.warm('bob');
    keys.watches['bob']!.addError(
      IdentityChangedException('bob', List.filled(64, 1)),
    );
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      cache.devices('bob'),
      throwsA(isA<IdentityChangedException>()),
    );
    // The person trusts the new key: the next send reads afresh and succeeds.
    keys.fetchError = null;
    expect(await cache.devices('bob'), isEmpty);
    expect(keys.fetched, ['bob', 'bob']);
  });

  test('a listener that fails is replaced on the next send', () async {
    final keys = _Keys();
    final cache = DeviceCache(
      keys,
      firstWait: const Duration(milliseconds: 20),
    );
    addTearDown(cache.close);
    cache.warm('bob');
    final first = keys.watches['bob']!;
    first.addError(StateError('listener ended'));
    await Future<void>.delayed(Duration.zero);
    expect(await cache.devices('bob'), isEmpty);
    expect(keys.fetched, ['bob']);
    expect(keys.watches['bob'], isNot(same(first)), reason: 'a new listener');
  });

  test('at most capacity listeners run; the oldest stops first', () async {
    final keys = _Keys();
    final cache = DeviceCache(keys, capacity: 2);
    addTearDown(cache.close);
    cache
      ..warm('a')
      ..warm('b')
      ..warm('a') // used again: now the newest
      ..warm('c');
    await Future<void>.delayed(Duration.zero);
    expect(keys.watches['b']!.hasListener, isFalse);
    expect(keys.watches['a']!.hasListener, isTrue);
    expect(keys.watches['c']!.hasListener, isTrue);
    await cache.close();
    expect(keys.watches['a']!.hasListener, isFalse);
  });

  test('sends read no device list once the chat is open, and a device '
      'linked later still gets the next message', () async {
    final db = FakeFirebaseFirestore();
    await addUser(db, 'alice', 'alice');
    await addUser(db, 'bob', 'bob');
    final alice = await Dev.create(db, 'alice');
    final keys = _CountingKeys(db, alice.secrets);
    final sender = ChatService(
      db: db,
      uid: 'alice',
      device: await alice.keys.ensureDevice('alice'),
      keys: keys,
      prekeys: PreKeyService(db, alice.secrets),
      secrets: alice.secrets,
      messages: alice.messages,
    );
    addTearDown(sender.close);
    final bob = await Dev.create(db, 'bob');
    final chatId = await sender.startChat('bob');
    await bob.chat.acceptRequest(chatId);
    bob.sync(chatId);
    addTearDown(bob.close);

    sender.prepareToSend(chatId);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    for (final text in ['one', 'two', 'three']) {
      await sender.sendText(chatId, text);
    }
    expect(keys.fetches, 0, reason: 'devices came from the listener');
    await eventually(
      () async => (await bob.history(chatId)).length == 3,
      why: 'all three delivered',
    );

    final bob2 = await Dev.linked(db, bob);
    bob2.sync(chatId);
    addTearDown(bob2.close);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sender.sendText(chatId, 'for both phones');
    await eventually(
      () async =>
          (await bob2.history(chatId)).any((m) => m.body == 'for both phones'),
      why: 'the new device received the next message',
    );
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the Firestore message count each time a session is persisted.
class SpySecretStore extends MemorySecretStore {
  SpySecretStore(this.db);
  final FakeFirebaseFirestore db;
  final sessionSaveSawMessages = <int>[];
  @override
  Future<void> write(String key, String value) async {
    if (key.startsWith('sess:')) {
      sessionSaveSawMessages.add(
        (await db.collection('chats/alice_bob/messages').get()).docs.length,
      );
    }
    await super.write(key, value);
  }
}

/// Fails the first N history writes, like a full disk.
class FlakyMessageStore extends MemoryMessageStore {
  FlakyMessageStore(this.failures);
  int failures;
  @override
  Future<void> add(LocalMessage m) async {
    if (failures > 0) {
      failures--;
      throw StateError('disk full');
    }
    return super.add(m);
  }
}

class Phone {
  Phone(this.db, this.uid, this.secrets, this.messages) {
    keys = KeyService(db, secrets);
  }
  final FakeFirebaseFirestore db;
  final String uid;
  final MemorySecretStore secrets;
  final MemoryMessageStore messages;
  late final KeyService keys;
  late final LocalDevice device;
  late final PreKeyService prekeys;
  late ChatService chat;
  final subs = <StreamSubscription<void>>[];

  static Future<Phone> create(
    FakeFirebaseFirestore db,
    String uid, {
    MemorySecretStore? secrets,
    MemoryMessageStore? messages,
  }) async {
    final p = Phone(
      db,
      uid,
      secrets ?? MemorySecretStore(),
      messages ?? MemoryMessageStore(),
    );
    p.device = await p.keys.ensureDevice(uid);
    p.prekeys = PreKeyService(db, p.secrets);
    await p.prekeys.maintain(uid, p.device);
    p.rebuild();
    return p;
  }

  void rebuild() => chat = ChatService(
    db: db,
    uid: uid,
    device: device,
    keys: keys,
    prekeys: prekeys,
    secrets: secrets,
    messages: messages,
  );

  void sync(String chatId) => subs.add(chat.startSync(chatId));
  Future<void> stopSync() async {
    for (final s in subs) {
      await s.cancel();
    }
    subs.clear();
  }

  Future<List<String>> bodies(String chatId) async =>
      (await messages.watch(chatId).first).map((m) => m.body).toList();
}

Future<void> eventually(Future<bool> Function() cond, String why) async {
  for (var i = 0; i < 150; i++) {
    if (await cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  fail('timed out: $why');
}

Future<void> addUser(FakeFirebaseFirestore db, String uid) async {
  await db.collection('usernames').doc(uid).set({'uid': uid});
  await db.collection('users').doc(uid).set({
    'username': uid,
    'displayName': uid,
  });
}

void main() {
  late FakeFirebaseFirestore db;
  const chatId = 'alice_bob';
  setUp(() async {
    db = FakeFirebaseFirestore();
    await addUser(db, 'alice');
    await addUser(db, 'bob');
  });

  test('S4: malformed documents do not block later messages', () async {
    final alice = await Phone.create(db, 'alice');
    final bob = await Phone.create(db, 'bob');
    await alice.chat.startChat('bob');
    final col = db.collection('chats/$chatId/messages');
    await col.doc('bad1').set({
      'ts': Timestamp.fromMillisecondsSinceEpoch(1000),
    }); // no sender
    await col.doc('bad2').set({
      'senderUid': 7,
      'senderDevice': 'x',
      'ts': Timestamp.fromMillisecondsSinceEpoch(2000),
    });
    await col.doc('bad3').set({
      'senderUid': 'alice',
      'senderDevice': alice.device.keys.deviceId,
      'ts': Timestamp.fromMillisecondsSinceEpoch(3000),
      'envelopes': {
        bob.device.keys.deviceId: {'n': 'not-a-number', 'sid': 5},
      },
    });
    await col.doc('bad4').set({
      'senderUid': 'alice',
      'senderDevice': 'd',
      'ts': Timestamp.fromMillisecondsSinceEpoch(4000),
      'envelopes': ['not', 'a', 'map'],
    });
    await alice.chat.sendText(chatId, 'real message after the junk');
    bob.sync(chatId);
    await eventually(
      () async =>
          (await bob.bodies(chatId)).contains('real message after the junk'),
      'real message arrives',
    );
    final all = await bob.messages.watch(chatId).first;
    expect(
      all.where((m) => m.status == MessageStatus.undecryptable),
      hasLength(2),
    );
    expect(all.map((m) => m.id), isNot(contains('bad1')));
    expect(all.map((m) => m.id), isNot(contains('bad2')));
    expect(all.map((m) => m.id), containsAll(['bad3', 'bad4']));
    await bob.stopSync();
  });

  test('S3: an authenticated but malformed payload spends the key, stores a placeholder, next message works', () async {
    final alice = await Phone.create(db, 'alice');
    final bob = await Phone.create(db, 'bob');
    await alice.chat.startChat('bob');
    // Alice's device builds a valid envelope whose plaintext is not JSON.
    final (s, _) = await Session.initiate(
      local: alice.device.keys,
      localBundle: alice.device.bundle,
      remote: await alice.prekeys.fetchBundle(
        (await alice.keys.fetchDevices('bob')).single,
      ),
    );
    final env = await s.encrypt(
      utf8.encode('this is not json'),
      chatId: chatId,
    );
    await db.collection('chats/$chatId/messages').doc('m1').set({
      'senderUid': 'alice',
      'senderDevice': alice.device.keys.deviceId,
      'ts': Timestamp.now(),
      'envelopes': {bob.device.keys.deviceId: env.toJson()},
    });
    bob.sync(chatId);
    await eventually(
      () async => (await bob.bodies(chatId)).contains('Malformed message.'),
      'placeholder',
    );
    // the session was saved: a second message on the same session decrypts
    final env2 = await s.encrypt(
      utf8.encode(jsonEncode({'type': 'text', 'body': 'second'})),
      chatId: chatId,
    );
    await db.collection('chats/$chatId/messages').doc('m2').set({
      'senderUid': 'alice',
      'senderDevice': alice.device.keys.deviceId,
      'ts': Timestamp.now(),
      'envelopes': {bob.device.keys.deviceId: env2.toJson()},
    });
    await eventually(
      () async => (await bob.bodies(chatId)).contains('second'),
      'second message',
    );
    await bob.stopSync();
  });

  test('S3: a failed history write does not burn the key; retry recovers the message', () async {
    final alice = await Phone.create(db, 'alice');
    final flaky = FlakyMessageStore(1);
    final bob = await Phone.create(db, 'bob', messages: flaky);
    await alice.chat.startChat('bob');
    await alice.chat.sendText(chatId, 'must survive a disk error');
    bob.sync(chatId);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(await bob.bodies(chatId), isEmpty);
    await bob.chat.retryDeferred();
    expect(await bob.bodies(chatId), ['must survive a disk error']);
    await bob.stopSync();
  });

  test('M-1: ratchets are written BEFORE publishing (never publish at a counter that was not saved)', () async {
    final spy = SpySecretStore(db);
    final alice = await Phone.create(db, 'alice', secrets: spy);
    await Phone.create(db, 'bob');
    await alice.chat.startChat('bob');
    spy.sessionSaveSawMessages.clear();
    await alice.chat.sendText(chatId, 'order matters');
    expect(spy.sessionSaveSawMessages, isNotEmpty);
    expect(spy.sessionSaveSawMessages.every((n) => n == 0), isTrue);
  });

  test('S2: failing to bump lastMessageAt does not report a published message as failed', () async {
    final alice = await Phone.create(db, 'alice');
    await Phone.create(db, 'bob');
    await alice.chat.startChat('bob');
    await db
        .collection('chats')
        .doc(chatId)
        .delete(); // makes the timestamp update fail
    await alice.chat.sendText(chatId, 'sent anyway');
    expect(await alice.bodies(chatId), ['sent anyway']);
    expect(
      (await db.collection('chats/$chatId/messages').get()).docs,
      hasLength(1),
    );
  });

  test(
    'S7: after being offline for 70 messages everything arrives, in order',
    () async {
      final alice = await Phone.create(db, 'alice');
      final bob = await Phone.create(db, 'bob');
      await alice.chat.startChat('bob');
      await bob.chat.acceptRequest(chatId);
      bob.sync(chatId);
      await alice.chat.sendText(chatId, 'first');
      await eventually(
        () async => (await bob.bodies(chatId)).contains('first'),
        'first',
      );
      await bob.stopSync(); // "app closed"
      for (var i = 0; i < 70; i++) {
        await alice.chat.sendText(chatId, 'offline $i');
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      bob.sync(chatId); // reopen
      await eventually(
        () async => (await bob.bodies(chatId)).contains('offline 69'),
        'caught up',
      );
      final got = await bob.bodies(chatId);
      expect(got.where((b) => b.startsWith('offline')), hasLength(70));
      expect(got.first, 'first');
      expect(got.where((b) => b.startsWith('offline')).toList(), [
        for (var i = 0; i < 70; i++) 'offline $i',
      ]);
      await bob.stopSync();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('S6: a changed contact identity defers messages; accepting it and retrying delivers them', () async {
    final alice = await Phone.create(db, 'alice');
    final bob = await Phone.create(db, 'bob');
    await alice.chat.startChat('bob');
    await bob.keys.fetchDevices('alice'); // bob pins alice's real identity
    // A device appears under a different identity and sends bob a message.
    final evilId = await AccountIdentity.generate();
    final evilKeys = await DeviceKeys.generate();
    final evil = await evilKeys.certify(evilId, 'alice');
    await db.collection('users/alice/devices').doc(evilKeys.deviceId).set({
      ...evil.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    final (s, _) = await Session.initiate(
      local: evilKeys,
      localBundle: evil,
      remote: await bob.prekeys.fetchBundle(bob.device.bundle),
    );
    final env = await s.encrypt(
      utf8.encode(
        jsonEncode({'type': 'text', 'body': 'from the new identity'}),
      ),
      chatId: chatId,
    );
    await db.collection('chats/$chatId/messages').doc('m1').set({
      'senderUid': 'alice',
      'senderDevice': evilKeys.deviceId,
      'ts': Timestamp.now(),
      'envelopes': {bob.device.keys.deviceId: env.toJson()},
    });
    bob.sync(chatId);
    await eventually(
      () async => bob.chat.identityAlertPeers.contains('alice'),
      'alert raised',
    );
    expect(await bob.bodies(chatId), isEmpty);
    await bob.keys.acceptIdentityChange('alice', evilId.publicBytes);
    await bob.chat.retryDeferred();
    expect(await bob.bodies(chatId), ['from the new identity']);
    expect(bob.chat.identityAlertPeers, isEmpty);
    await bob.stopSync();
  });
}

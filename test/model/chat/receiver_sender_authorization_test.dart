import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

class Dev {
  Dev(this.db, this.uid, this.secrets, this.keys, this.messages);
  final FakeFirebaseFirestore db;
  final String uid;
  final MemorySecretStore secrets;
  final KeyService keys;
  final MemoryMessageStore messages;
  late ChatService chat;
  late LocalDevice device;
  final subs = <StreamSubscription<void>>[];

  static Future<Dev> create(FakeFirebaseFirestore db, String uid) async {
    final secrets = MemorySecretStore();
    final d = Dev(
      db,
      uid,
      secrets,
      KeyService(db, secrets),
      MemoryMessageStore(),
    );
    d.device = await d.keys.ensureDevice(uid);
    d.chat = ChatService(
      db: db,
      uid: uid,
      device: d.device,
      keys: d.keys,
      prekeys: PreKeyService(db, secrets),
      secrets: secrets,
      messages: d.messages,
    );
    await PreKeyService(db, secrets).maintain(uid, d.device);
    return d;
  }

  Future<List<LocalMessage>> history(String chatId) =>
      messages.watch(chatId).first;
  Future<void> close() async {
    await chat.close();
    for (final s in subs) {
      await s.cancel();
    }
  }
}

Future<void> addUser(FakeFirebaseFirestore db, String uid, String name) async {
  await db.collection('usernames').doc(name).set({'uid': uid});
  await db.collection('users').doc(uid).set({
    'username': name,
    'displayName': name,
  });
}

Future<void> waitForCursor(Dev device, String chatId) async {
  final key = 'cursor:${device.device.keys.deviceId}:$chatId';
  for (var i = 0; i < 100; i++) {
    if (device.secrets.data.containsKey(key)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('receive processing did not reach its durable cursor');
}

void main() {
  test(
    'a message whose sender is not the chat peer is dropped, not shown',
    () async {
      final db = FakeFirebaseFirestore();
      await addUser(db, 'alice', 'alice');
      await addUser(db, 'bob', 'bob');

      final alice = await Dev.create(db, 'alice');
      final bob = await Dev.create(db, 'bob');
      final chatId = await alice.chat.startChat('bob');

      await db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc('injected')
          .set({
            'senderUid': 'stranger',
            'senderDevice': 'stranger-device',
            'ts': Timestamp.now(),
            'envelopes': {
              bob.device.keys.deviceId: {'pv': 4, 'n': 0, 'pn': 0, 'sid': 'x'},
            },
          });

      bob.subs.add(bob.chat.startSync(chatId));

      // Waiting for the durable cursor proves processing finished, rather than
      // passing merely because the listener has not run yet.
      await waitForCursor(bob, chatId);
      expect(await bob.history(chatId), isEmpty);
      expect(
        bob.secrets.data.keys.where((k) => k.startsWith('sess:')),
        isEmpty,
      );

      await alice.close();
      await bob.close();
    },
  );
  test('a rejected sender does not stop the valid peer or cursor', () async {
    final db = FakeFirebaseFirestore();
    final bob = await Dev.create(db, 'bob');
    addTearDown(bob.close);
    const chatId = 'alice_bob';
    final messages = db.collection('chats').doc(chatId).collection('messages');
    await messages.doc('bad').set({
      'senderUid': 'stranger',
      'senderDevice': 'other-device',
      'ts': Timestamp(1, 0),
    });
    await messages.doc('good').set({
      'senderUid': 'alice',
      'senderDevice': 'alice-device',
      'ts': Timestamp(2, 0),
    });
    bob.subs.add(bob.chat.startSync(chatId));
    await waitForCursor(bob, chatId);
    final history = await bob.history(chatId);
    expect(history.map((m) => m.id), ['good']);
    expect(history.single.senderUid, 'alice');
    expect(history.single.outgoing, isFalse);
    expect(
      bob.secrets.data['cursor:${bob.device.keys.deviceId}:$chatId'],
      '2:0',
    );
  });

  test('an invalid chat cannot confirm an unrelated pending send', () async {
    final db = FakeFirebaseFirestore();
    final bob = await Dev.create(db, 'bob');
    addTearDown(bob.close);
    const chatId = 'alice_stranger';
    await bob.messages.add(
      LocalMessage(
        id: 'pending',
        chatId: chatId,
        senderUid: 'bob',
        senderDevice: bob.device.keys.deviceId,
        outgoing: true,
        sentAt: DateTime(2026),
        body: 'local pending',
        status: MessageStatus.unconfirmed,
      ),
    );
    await db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc('pending')
        .set({
          'senderUid': 'bob',
          'senderDevice': bob.device.keys.deviceId,
          'ts': Timestamp(1, 0),
        });
    bob.subs.add(bob.chat.startSync(chatId));
    await waitForCursor(bob, chatId);
    expect(
      (await bob.history(chatId)).single.status,
      MessageStatus.unconfirmed,
    );
  });
}

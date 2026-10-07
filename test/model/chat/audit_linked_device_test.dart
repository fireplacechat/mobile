// Linked devices keep device-level receive bookkeeping in storage while the
// account's public history stream supplies the correct presentation direction.
// The harness is based on chat_service_test.dart.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
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
    await d._init(await d.keys.ensureDevice(uid));
    return d;
  }

  static Future<Dev> linked(FakeFirebaseFirestore db, Dev existing) async {
    final secrets = MemorySecretStore();
    final identity = (await existing.keys.ensureDevice(existing.uid)).identity;
    final dk = await DeviceKeys.generate();
    final bundle = await dk.certify(identity, existing.uid);
    await db
        .collection('users')
        .doc(existing.uid)
        .collection('devices')
        .doc(dk.deviceId)
        .set({
          ...bundle.toFirestore(),
          'createdAt': FieldValue.serverTimestamp(),
        });
    final d = Dev(
      db,
      existing.uid,
      secrets,
      KeyService(db, secrets),
      MemoryMessageStore(),
    );
    await d._init(LocalDevice(identity, dk, bundle));
    return d;
  }

  Future<void> _init(LocalDevice ld) async {
    chat = ChatService(
      db: db,
      uid: uid,
      device: ld,
      keys: keys,
      prekeys: PreKeyService(db, secrets),
      secrets: secrets,
      messages: messages,
    );
    await PreKeyService(db, secrets).maintain(uid, ld);
  }

  Future<List<LocalMessage>> history(String chatId) =>
      messages.watch(chatId).first;
  void sync(String chatId) => subs.add(chat.startSync(chatId));
  Future<void> close() async {
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

Future<void> eventually(Future<bool> Function() cond, {String? why}) async {
  for (var i = 0; i < 150; i++) {
    if (await cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  fail('condition not met: ${why ?? ''}');
}

void main() {
  test('linked-device own send is outgoing in account-relative history', () async {
    final db = FakeFirebaseFirestore();
    await addUser(db, 'alice', 'alice');
    await addUser(db, 'bob', 'bob');

    final alice1 = await Dev.create(db, 'alice'); // primary device
    final alice2 = await Dev.linked(db, alice1); // second device, same identity
    final bob = await Dev.create(db, 'bob');

    final chatId = await alice1.chat.startChat('bob');
    bob.sync(chatId);
    alice2.sync(chatId); // the linked device is watching the same chat

    // Alice sends from device 1. The sender fans the ciphertext out to Bob AND
    // to Alice's own other devices, so device 2 receives a copy.
    await alice1.chat.sendText(chatId, 'sent from my first phone');

    // Bob gets it correctly as incoming.
    await eventually(
      () async =>
          (await bob.history(chatId))
              .any((m) => m.body == 'sent from my first phone'),
      why: 'bob never received',
    );

    // Device 2 also stores it...
    await eventually(
      () async =>
          (await alice2.history(chatId))
              .any((m) => m.body == 'sent from my first phone'),
      why: 'linked device never stored the copy',
    );

    final onDevice2 = (await alice2.history(chatId))
        .firstWhere((m) => m.body == 'sent from my first phone');

    // Receive bookkeeping remains device-relative; the UI stream must identify
    // this as Alice's own message without rewriting protocol state.
    expect(
      onDevice2.outgoing,
      isFalse,
      reason: 'device receive bookkeeping remains unchanged',
    );
    final displayed = (await alice2.chat.watchMessages(chatId).first)
        .singleWhere((m) => m.id == onDevice2.id);
    expect(
      displayed.outgoing,
      isTrue,
      reason:
          'EXPECTED a message the user sent from another of their own devices to be '
          'shown as outgoing on this device. It is stored as incoming instead '
          '(outgoing=${onDevice2.outgoing}, senderUid=${onDevice2.senderUid}).',
    );

    await alice1.chat.close();
    await alice2.chat.close();
    await bob.chat.close();
    await alice1.close();
    await alice2.close();
    await bob.close();
  });
}

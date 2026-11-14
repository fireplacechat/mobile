import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

const chatId = 'alice_bob';

class Phone {
  Phone(this.db, this.uid);
  final FakeFirebaseFirestore db;
  final String uid;
  final secrets = MemorySecretStore();
  final messages = MemoryMessageStore();
  late final SafetyService safety;
  late final ChatService chat;

  static Future<Phone> create(FakeFirebaseFirestore db, String uid) async {
    final p = Phone(db, uid);
    final keys = KeyService(db, p.secrets);
    final device = await keys.ensureDevice(uid);
    final prekeys = PreKeyService(db, p.secrets);
    await prekeys.maintain(uid, device);
    p.safety = SafetyService(db, p.secrets, uid);
    await p.safety.start();
    p.chat = ChatService(
      db: db,
      uid: uid,
      device: device,
      keys: keys,
      prekeys: prekeys,
      secrets: p.secrets,
      messages: p.messages,
      safety: p.safety,
      commitBatch: (batch) async {
        final peer = uid == 'alice' ? 'bob' : 'alice';
        // Model the production rule at the publish boundary: fake Firestore
        // otherwise accepts blocked messages, hiding refused-send bugs.
        if ((await db.doc('users/$peer/blocks/$uid').get()).exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          );
        }
        await batch.commit();
      },
    );
    return p;
  }

  Future<void> receive() async {
    await chat.receiveOnce(chatId);
  }

  Future<List<LocalMessage>> history() => messages.watch(chatId).first;

  Future<void> close() async {
    await chat.close();
    await safety.dispose();
  }
}

void main() {
  for (final established in [false, true]) {
    test('refused sends survive unblock, established=$established', () async {
      final db = FakeFirebaseFirestore();
      for (final uid in ['alice', 'bob']) {
        await db.doc('usernames/$uid').set({'uid': uid});
        await db.doc('users/$uid').set({'username': uid});
      }
      final alice = await Phone.create(db, 'alice');
      final bob = await Phone.create(db, 'bob');
      addTearDown(alice.close);
      addTearDown(bob.close);
      await alice.chat.startChat('bob');
      await bob.chat.acceptRequest(chatId);
      if (established) {
        await alice.chat.sendText(chatId, 'hello');
        await bob.receive();
        await bob.chat.sendText(chatId, 'reply');
        await alice.receive();
      }
      for (var cycle = 0; cycle < 3; cycle++) {
        await alice.safety.block('bob');
        for (var attempt = 0; attempt < 3; attempt++) {
          await expectLater(
            bob.chat.sendText(chatId, 'refused $cycle/$attempt'),
            throwsA(isA<ChatException>()),
          );
        }
        await alice.safety.unblock('bob');
        await bob.chat.sendText(chatId, 'bob $cycle');
        await alice.receive();
        expect((await alice.history()).last.body, 'bob $cycle');
        await alice.chat.sendText(chatId, 'alice $cycle');
        await bob.receive();
        expect((await bob.history()).last.body, 'alice $cycle');
      }
      for (final phone in [alice, bob]) {
        expect(
          (await phone.history()).every((m) => m.status == MessageStatus.ok),
          isTrue,
        );
      }
    });
  }
}

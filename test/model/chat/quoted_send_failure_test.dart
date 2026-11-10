import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'durability_test.dart' show Phone, fb;

void main() {
  for (final committed in [false, true]) {
    test(
      'uncertain reply retains quote and never republishes on check ($committed)',
      () async {
        final db = FakeFirebaseFirestore();
        for (final uid in ['alice', 'bob']) {
          await db.collection('users').doc(uid).set({'username': uid});
          await db.collection('usernames').doc(uid).set({'uid': uid});
        }
        final alice = await Phone.create(db, 'alice');
        final bob = await Phone.create(db, 'bob');
        addTearDown(() async {
          await alice.chat.close();
          await bob.chat.close();
        });
        const chat = 'alice_bob';
        await alice.chat.startChat('bob');
        await bob.chat.acceptRequest(chat);
        await alice.chat.sendText(chat, 'Original');
        final original = (await alice.messages.watch(chat).first).single;
        alice.commit = (batch) async {
          if (committed) await batch.commit();
          throw fb('unavailable');
        };
        SendNotConfirmedException? pending;
        try {
          await alice.chat.sendReply(chat, 'Answer', original.id);
        } on SendNotConfirmedException catch (e) {
          pending = e;
        }
        expect(pending!.quote!.targetId, original.id);
        alice.commit = null;
        await alice.chat.close();
        alice.restart();
        final outcome = await alice.chat.checkSendStatus(
          chat,
          pending.messageId,
        );
        expect(
          outcome,
          committed ? SendOutcome.confirmed : SendOutcome.publishUnknown,
        );
        final stored = await alice.messages.get(chat, pending.messageId);
        expect(stored!.quote!.body, 'Original');
        expect(
          (await db.collection('chats/$chat/messages').get()).docs.length,
          committed ? 2 : 1,
        );
      },
    );
  }
}

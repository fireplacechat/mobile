import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'durability_test.dart' show Phone, fb, eventually;

void main() {
  for (final committed in [false, true]) {
    test(
      'unknown edit outcome (committed=$committed) never publishes twice',
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
        await alice.chat.sendText(chat, 'first');
        final id = (await alice.messages.watch(chat).first).single.id;
        final sessionBefore = await alice.secrets.read(alice.sessKey(bob));
        alice.commit = (batch) async {
          if (committed) await batch.commit();
          throw fb('unavailable');
        };
        SendNotConfirmedException? pending;
        try {
          await alice.chat.editMessage(chat, id, 'Corrected');
        } on SendNotConfirmedException catch (e) {
          pending = e;
        }
        expect(pending, isNotNull);
        expect(pending!.mutation, isNotNull);
        expect((await alice.messages.watch(chat).first).single.edits, isEmpty);
        expect(
          await alice.secrets.read(alice.sessKey(bob)),
          isNot(sessionBefore),
        );
        alice.commit = null;
        final outcome = await alice.chat.checkSendStatus(
          chat,
          pending.messageId,
        );
        expect(
          outcome,
          committed ? SendOutcome.confirmed : SendOutcome.publishUnknown,
        );
        expect(
          (await db.collection('chats/$chat/messages').get()).docs.length,
          committed ? 2 : 1,
        );
        if (committed) {
          expect(
            (await alice.messages.watch(chat).first).single.body,
            'Corrected',
          );
        }
        await alice.chat.sendText(chat, 'after control');
        final sub = bob.chat.startSync(chat);
        addTearDown(sub.cancel);
        await eventually(
          () async => (await bob.bodies(chat)).contains('after control'),
          'ratchet continues',
        );
        expect(
          (await bob.messages.watch(chat).first).every(
            (m) => m.status == MessageStatus.ok,
          ),
          isTrue,
        );
      },
    );
  }
}

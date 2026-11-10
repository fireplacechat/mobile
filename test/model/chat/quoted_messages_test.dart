import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';

import 'chat_service_test.dart' show Dev, addUser, eventually;

void main() {
  test(
    'replies encrypt the bounded quote for both people and linked devices',
    () async {
      final db = FakeFirebaseFirestore();
      await addUser(db, 'alice', 'alice');
      await addUser(db, 'bob', 'bob');
      final alice = await Dev.create(db, 'alice'),
          bob = await Dev.create(db, 'bob');
      final linked = await Dev.linked(db, alice);
      addTearDown(() async {
        for (final d in [alice, bob, linked]) {
          await d.close();
          await d.chat.close();
        }
      });
      const chat = 'alice_bob';
      await db.collection('chats').doc(chat).set({
        'members': ['alice', 'bob'],
        'accepted': true,
      });
      for (final d in [alice, bob, linked]) {
        d.sync(chat);
      }
      await bob.chat.sendText(chat, 'Fictional original ${'😀' * 1100}');
      await eventually(() async => (await alice.history(chat)).length == 1);
      final original = (await alice.history(chat)).single;
      await alice.chat.sendReply(chat, 'A quoted answer', original.id);
      await eventually(
        () async =>
            (await linked.history(chat)).length == 2 &&
            (await bob.history(chat)).length == 2,
      );
      for (final d in [alice, bob, linked]) {
        final reply = (await d.history(chat)).last;
        expect(reply.quote!.targetId, original.id);
        expect(reply.quote!.senderUid, 'bob');
        expect(reply.quote!.body.runes.length, 1024);
      }
      expect(db.dump(), isNot(contains('A quoted answer')));
      await bob.chat.deleteForEveryone(chat, original.id);
      await eventually(
        () async => (await alice.history(chat)).last.quote!.unavailable,
      );
      await expectLater(
        alice.chat.sendReply(chat, 'Again', original.id),
        throwsA(isA<ChatException>()),
      );
    },
  );
}

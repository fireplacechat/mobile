import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';

import 'chat_service_test.dart' show Dev, addUser, eventually;

void main() {
  test(
    'encrypted reactions, linked copies and remote delete use normal envelopes',
    () async {
      final db = FakeFirebaseFirestore();
      await addUser(db, 'alice', 'alice');
      await addUser(db, 'bob', 'bob');
      final alice = await Dev.create(db, 'alice');
      final bob = await Dev.create(db, 'bob');
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
      await alice.chat.sendText(chat, 'original fictional message');
      await eventually(
        () async =>
            (await bob.history(chat)).isNotEmpty &&
            (await linked.history(chat)).isNotEmpty,
      );
      final id = (await alice.history(chat)).single.id;
      await bob.chat.react(chat, id, '❤️');
      await eventually(
        () async =>
            (await linked.history(chat)).single.reactions['bob']?.emoji == '❤️',
      );
      expect((await alice.history(chat)).single.reactions['bob']?.emoji, '❤️');
      await bob.chat.react(chat, id, '❤️');
      await eventually(
        () async =>
            (await alice.history(chat)).single.reactions['bob']?.revision == 2,
      );
      expect(
        (await alice.history(chat)).single.reactions['bob']!.emoji,
        isNull,
      );
      await expectLater(
        bob.chat.deleteForEveryone(chat, id),
        throwsA(isA<ChatException>()),
      );
      await linked.chat.deleteForEveryone(chat, id);
      await eventually(
        () async => (await bob.history(chat)).single.remotelyDeleted,
      );
      await eventually(
        () async => (await alice.history(chat)).single.remotelyDeleted,
      );
      expect((await bob.history(chat)).single.body, isEmpty);
      final docs = await db
          .collection('chats')
          .doc(chat)
          .collection('messages')
          .get();
      expect(docs.docs, hasLength(4));
      for (final doc in docs.docs) {
        expect(doc.data().keys.toSet(), {
          'senderUid',
          'senderDevice',
          'ts',
          'envelopes',
          'expireAt',
        });
      }
      expect(db.dump(), isNot(contains('original fictional message')));
      expect(db.dump(), isNot(contains('❤️')));
    },
  );
}

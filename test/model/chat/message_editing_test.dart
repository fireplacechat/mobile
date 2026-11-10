import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/model/chat/message_content.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/model/chat/chat_exceptions.dart';

import 'chat_service_test.dart' show Dev, addUser, eventually;

void main() {
  test('author edits and history reach both people and linked devices with reactions intact', () async {
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
    await alice.chat.sendText(chat, 'Meet on Monday');
    await eventually(
      () async =>
          (await linked.history(chat)).isNotEmpty &&
          (await bob.history(chat)).isNotEmpty,
    );
    final id = (await alice.history(chat)).single.id;
    await bob.chat.react(chat, id, '👍');
    await alice.chat.editMessage(chat, id, 'Meet on Tuesday');
    await eventually(
      () async => (await linked.history(chat)).single.body == 'Meet on Tuesday',
    );
    await linked.chat.editMessage(chat, id, 'Meet on Wednesday');
    await eventually(
      () async =>
          (await bob.history(chat)).single.edits.length == 2 &&
          (await alice.history(chat)).single.edits.length == 2,
    );
    for (final d in [alice, bob, linked]) {
      final result = (await d.history(chat)).single;
      expect(result.body, 'Meet on Wednesday');
      expect(result.originalBody, 'Meet on Monday');
      expect(result.reactions['bob']!.emoji, '👍');
    }
    await expectLater(
      bob.chat.editMessage(chat, id, 'Forged'),
      throwsA(isA<ChatException>()),
    );
    expect(db.dump(), isNot(contains('Meet on')));
    for (final doc
        in (await db.collection('chats/$chat/messages').get()).docs) {
      expect(doc.data().keys.toSet(), {
        'senderUid',
        'senderDevice',
        'ts',
        'envelopes',
        'expireAt',
      });
    }
  });
  test(
    'sender enforces age, ten revisions, changed body and Unicode limit',
    () async {
      final store = MemoryMessageStore();
      for (final (id, age, clock) in [
        ('old', const Duration(hours: 25), 0),
        ('full', Duration.zero, 10),
        ('ok', Duration.zero, 0),
      ]) {
        await store.add(
          LocalMessage(
            id: id,
            chatId: 'alice_bob',
            senderUid: 'alice',
            senderDevice: 'a',
            outgoing: true,
            sentAt: DateTime.now().subtract(age),
            body: 'Original',
            editClock: clock,
          ),
        );
      }
      Future<Object> prepare(String id, String body) => prepareMessageContent(
        messages: store,
        uid: 'alice',
        chatId: 'alice_bob',
        text: '',
        mutation: MessageMutation(
          kind: MessageMutationKind.edit,
          targetId: id,
          body: body,
        ),
      );
      for (final id in ['old', 'full']) {
        await expectLater(
          prepare(id, 'Changed'),
          throwsA(isA<ChatException>()),
        );
      }
      await expectLater(
        prepare('ok', 'Original'),
        throwsA(isA<ChatException>()),
      );
      await expectLater(
        prepare('ok', '😀' * 16385),
        throwsA(isA<ChatException>()),
      );
      await prepare('ok', '😀' * 16384);
    },
  );

  test('an older message you sent can still be deleted for everyone', () async {
    final store = MemoryMessageStore();
    await store.add(
      LocalMessage(
        id: 'old',
        chatId: 'alice_bob',
        senderUid: 'alice',
        senderDevice: 'a',
        outgoing: true,
        sentAt: DateTime.now().subtract(const Duration(days: 30)),
        body: 'Original',
      ),
    );
    await store.add(
      LocalMessage(
        id: 'theirs',
        chatId: 'alice_bob',
        senderUid: 'bob',
        senderDevice: 'b',
        outgoing: false,
        sentAt: DateTime.now(),
        body: 'From Bob',
      ),
    );
    Future<Object> prepare(String id) => prepareMessageContent(
      messages: store,
      uid: 'alice',
      chatId: 'alice_bob',
      text: '',
      mutation: MessageMutation(kind: MessageMutationKind.delete, targetId: id),
    );
    final own = await prepare('old');
    expect(
      (own as ({MessageQuote? quote, MessageMutation? mutation}))
          .mutation
          ?.kind,
      MessageMutationKind.delete,
    );
    await expectLater(prepare('theirs'), throwsA(isA<ChatException>()));
  });
}

// An edit, a delete and a reaction taken back are sent as quiet messages
// (decision 0054): the server sends no alert for them. A text and a new
// reaction are ordinary messages.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_service_test.dart' show Dev, addUser, eventually;

void main() {
  test('which changes are quiet', () {
    MessageMutation m(
      MessageMutationKind kind, [
      ReactionOperation op = ReactionOperation.set,
    ]) => MessageMutation(kind: kind, targetId: 'm1', operation: op);
    expect(m(MessageMutationKind.edit).quiet, isTrue);
    expect(m(MessageMutationKind.delete).quiet, isTrue);
    expect(
      m(MessageMutationKind.reaction, ReactionOperation.clear).quiet,
      isTrue,
    );
    expect(m(MessageMutationKind.reaction).quiet, isFalse);
  });

  test('the message document says so, and nothing else about itself', () async {
    final db = FakeFirebaseFirestore();
    await addUser(db, 'alice', 'alice');
    await addUser(db, 'bob', 'bob');
    final alice = await Dev.create(db, 'alice'),
        bob = await Dev.create(db, 'bob');
    addTearDown(() async {
      for (final d in [alice, bob]) {
        await d.close();
        await d.chat.close();
      }
    });
    const chat = 'alice_bob';
    await db.collection('chats').doc(chat).set({
      'members': ['alice', 'bob'],
      'accepted': true,
    });
    alice.sync(chat);
    bob.sync(chat);
    final col = db.collection('chats/$chat/messages');
    Future<Set<String>> ids() async => {
      for (final d in (await col.get()).docs) d.id,
    };
    Future<Map<String, dynamic>> newest(Set<String> before) async {
      final docs = (await col.get()).docs.where((d) => !before.contains(d.id));
      return docs.single.data();
    }

    var before = await ids();
    await alice.chat.sendText(chat, 'Hello Bob');
    expect((await newest(before)).containsKey('quiet'), isFalse);
    await eventually(() async => (await bob.history(chat)).length == 1);
    final target = (await alice.history(chat)).single.id;

    before = await ids();
    await bob.chat.react(chat, target, '👍');
    expect((await newest(before)).containsKey('quiet'), isFalse);
    await eventually(
      () async => (await alice.history(chat)).single.reactions.isNotEmpty,
    );

    // The same emoji again takes the reaction back.
    before = await ids();
    await bob.chat.react(chat, target, '👍');
    expect((await newest(before))['quiet'], isTrue);

    before = await ids();
    await alice.chat.editMessage(chat, target, 'Hello Bob!');
    final edit = await newest(before);
    expect(edit['quiet'], isTrue);
    // The same fields as any message, plus the mark.
    expect(edit.keys.toSet(), {
      'senderUid',
      'senderDevice',
      'ts',
      'envelopes',
      'expireAt',
      'quiet',
    });

    before = await ids();
    await alice.chat.deleteForEveryone(chat, target);
    expect((await newest(before))['quiet'], isTrue);
    // They still arrive and apply.
    await eventually(
      () async => (await bob.history(chat)).single.remotelyDeleted,
    );
  });
}

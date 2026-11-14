// Deleting a conversation on this phone (issue 123): the messages are erased
// here only, nothing is sent, and the conversation carries on afterwards.
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/chat/cleared_chats.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart' show message;
import 'chat_service_test.dart' show Dev, addUser, eventually;

void main() {
  test(
    'the messages go from this phone only, and the chat still works',
    () async {
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
      await alice.chat.sendText(chat, 'Hello Bob');
      await bob.chat.sendText(chat, 'Hello Alice');
      await eventually(() async => (await alice.history(chat)).length == 2);
      await eventually(() async => (await bob.history(chat)).length == 2);
      final server = (await db.collection('chats/$chat/messages').get()).size;

      expect(await alice.chat.clearedChats(), isEmpty);
      await alice.chat.deleteChatHere(chat);
      expect(await alice.history(chat), isEmpty);
      expect(await alice.chat.clearedChats(), {chat});
      // The server copy and Bob's copy are untouched.
      expect((await db.collection('chats/$chat/messages').get()).size, server);
      expect((await bob.history(chat)).length, 2);

      // Both directions still work, and nothing old comes back.
      await bob.chat.sendText(chat, 'Still there?');
      await eventually(() async => (await alice.history(chat)).length == 1);
      await alice.chat.sendText(chat, 'Yes');
      await eventually(() async => (await bob.history(chat)).length == 4);
      final texts = [for (final m in await alice.history(chat)) m.body];
      expect(texts, ['Still there?', 'Yes']);
      expect(
        (await alice.history(chat)).every((m) => m.status == MessageStatus.ok),
        isTrue,
      );
    },
  );

  for (final disk in [false, true]) {
    test('clearing erases every message and keeps replay suppressed '
        '(disk=$disk)', () async {
      final dir = Directory.systemTemp.createTempSync('fireplace_clear');
      addTearDown(() => dir.deleteSync(recursive: true));
      final secrets = MemorySecretStore();
      Future<LocalMessageStore> open() async => disk
          ? await EncryptedFileMessageStore.open(
              dir: dir,
              secrets: secrets,
              uid: 'alice',
            )
          : MemoryMessageStore();
      var store = await open();
      final first = message(id: 'one', body: 'private fictional text');
      final second = message(id: 'two', body: 'more of it', outgoing: true);
      await store.add(first);
      await store.add(second);
      await store.clearChat(first.chatId);
      expect(await store.watch(first.chatId).first, isEmpty);
      for (final m in [first, second]) {
        expect(await store.get(m.chatId, m.id), isNull);
        expect(await store.has(m.chatId, m.id), isTrue);
        // Seen again, it is not stored again.
        await store.add(m);
      }
      expect(await store.watch(first.chatId).first, isEmpty);
      // A chat with nothing in it is left alone.
      await store.clearChat('alice_nobody');
      if (disk) {
        await (store as EncryptedFileMessageStore).close();
        final files = dir.listSync(recursive: true).whereType<File>();
        for (final f in files) {
          expect(
            String.fromCharCodes(f.readAsBytesSync()),
            isNot(contains('private fictional text')),
          );
        }
        store = await open();
        expect(await store.watch(first.chatId).first, isEmpty);
        expect(await store.has(first.chatId, 'one'), isTrue);
        await (store as EncryptedFileMessageStore).close();
      }
      // New messages are kept as usual.
      if (!disk) {
        await store.add(message(id: 'three', body: 'after'));
        expect((await store.watch(first.chatId).first).single.body, 'after');
      }
    });
  }

  test('which chats were deleted here is remembered per account', () async {
    final secrets = MemorySecretStore();
    final cleared = ClearedChats(secrets, 'alice');
    await cleared.load();
    var changes = 0;
    final sub = cleared.changes.listen((_) => changes++);
    await cleared.add('alice_bob');
    await cleared.add('alice_bob');
    await Future<void>.delayed(Duration.zero);
    expect(changes, 1);
    await sub.cancel();
    final again = ClearedChats(secrets, 'alice');
    await again.load();
    expect(again.chats, {'alice_bob'});
    final other = ClearedChats(secrets, 'dana');
    await other.load();
    expect(other.chats, isEmpty);
    await secrets.write(ClearedChats.keyName('alice'), '{not json');
    final damaged = ClearedChats(secrets, 'alice');
    await damaged.load();
    expect(damaged.chats, isEmpty);
  });
}

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/chat/chat_directory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_linked_device_test.dart' show Dev, addUser, eventually;

void main() {
  test('the chat list listener keeps each chat document for sends', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('chats/alice_bob').set({
      'participants': ['alice', 'bob'],
      'accepted': true,
    });
    final directory = ChatDirectory(db, MemoryMessageStore(), 'alice', null);
    expect(directory.knownChat('alice_bob'), isNull);
    final sub = directory.watchChats().listen((_) {});
    addTearDown(sub.cancel);
    await eventually(
      () async => directory.knownChat('alice_bob') != null,
      why: 'seen by the listener',
    );
    expect(directory.knownChat('alice_bob')!['accepted'], isTrue);
    await db.doc('chats/alice_bob').delete();
    await eventually(
      () async => directory.knownChat('alice_bob') == null,
      why: 'a removed chat is forgotten',
    );
  });

  test(
    'a message request is still limited while the chat list listens',
    () async {
      final db = FakeFirebaseFirestore();
      await addUser(db, 'alice', 'alice');
      await addUser(db, 'bob', 'bob');
      final alice = await Dev.create(db, 'alice');
      await Dev.create(db, 'bob');
      final chatId = await alice.chat.startChat('bob');
      final sub = alice.chat.watchChats().listen((_) {});
      addTearDown(sub.cancel);
      for (var i = 0; i < ChatService.requestLimit; i++) {
        await alice.chat.sendText(chatId, 'hello $i');
      }
      await expectLater(
        alice.chat.sendText(chatId, 'one too many'),
        throwsA(isA<ChatException>()),
      );
    },
  );
}

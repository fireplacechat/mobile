import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ChatService alice;
  late MemoryMessageStore messages;
  const chatId = 'alice_bob';
  final release = Completer<void>();
  var bumps = 0;

  setUp(() async {
    final previousPacing = ChatService.pacing;
    ChatService.pacing = false;
    addTearDown(() => ChatService.pacing = previousPacing);
    db = FakeFirebaseFirestore();
    messages = MemoryMessageStore();
    for (final u in ['alice', 'bob']) {
      await db.collection('usernames').doc(u).set({'uid': u});
      await db.collection('users').doc(u).set({'username': u});
    }
    Future<ChatService> make(String uid, {bool holdBump = false}) async {
      final secrets = MemorySecretStore();
      final keys = KeyService(db, secrets);
      final device = await keys.ensureDevice(uid);
      final prekeys = PreKeyService(db, secrets);
      await prekeys.maintain(uid, device);
      return ChatService(
        db: db,
        uid: uid,
        device: device,
        keys: keys,
        prekeys: prekeys,
        secrets: secrets,
        messages: uid == 'alice' ? messages : MemoryMessageStore(),
        beforeChatListBump: holdBump
            ? () async {
                bumps++;
                await release.future;
              }
            : null,
      );
    }

    alice = await make('alice', holdBump: true);
    await make('bob');
    await alice.startChat('bob');
    await db.collection('chats').doc(chatId).update({
      'accepted': true,
      'lastMessageAt': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(hours: 2)),
      ),
    });
  });

  test('a chat-list bump does not keep the send from finishing', () async {
    var returned = false;
    final pending = alice
        .sendText(chatId, 'just one')
        .whenComplete(() => returned = true);
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!returned || bumps == 0) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the send did not finish while the chat-list bump waited');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect((await messages.watch(chatId).first).map((m) => m.body), [
      'just one',
    ]);
    expect(bumps, 1);
    var secondReturned = false;
    final second = alice
        .sendText(chatId, 'another')
        .whenComplete(() => secondReturned = true);
    while (!secondReturned) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the next send waited on the chat-list bump');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(bumps, 1);
    release.complete();
    await pending;
    await second;
    final stampDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      final stamp =
          (await db.doc('chats/$chatId').get()).data()!['lastMessageAt']
              as Timestamp;
      if (DateTime.now().difference(stamp.toDate()) <
          const Duration(minutes: 1)) {
        break;
      }
      if (DateTime.now().isAfter(stampDeadline)) {
        fail('the chat list was not reordered');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
}

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ChatService> makeChat(
  FakeFirebaseFirestore db,
  String uid,
  LocalMessageStore messages,
) async {
  await db.doc('users/$uid').set({'username': uid});
  await db.doc('usernames/$uid').set({'uid': uid});
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
    messages: messages,
  );
}

void main() {
  test(
    'documents current behaviour: sendText after close still completes',
    () async {
      final db = FakeFirebaseFirestore();
      final history = MemoryMessageStore();
      final fred = await makeChat(db, 'fred', history);
      final bob = await makeChat(db, 'bob', MemoryMessageStore());
      addTearDown(bob.close);
      addTearDown(fred.close);
      final chatId = await fred.startChat('bob');
      await bob.acceptRequest(chatId);
      await fred.close();
      await fred.sendText(chatId, 'after close');
      expect(
        (await db.collection('chats').doc(chatId).collection('messages').get())
            .docs,
        hasLength(1),
      );
      expect((await history.watch(chatId).first).map((m) => m.body), [
        'after close',
      ]);
    },
  );
}

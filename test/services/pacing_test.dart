import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ChatService alice;
  const chatId = 'alice_bob';

  setUp(() async {
    db = FakeFirebaseFirestore();
    for (final u in ['alice', 'bob']) {
      await db.collection('usernames').doc(u).set({'uid': u});
      await db.collection('users').doc(u).set({'username': u});
    }
    Future<ChatService> make(String uid) async {
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
        messages: MemoryMessageStore(),
      );
    }

    alice = await make('alice');
    await make('bob');
    await alice.startChat('bob');
    // an accepted chat whose last activity is recent
    await db.collection('chats').doc(chatId).update({
      'accepted': true,
      'lastMessageAt': Timestamp.now(),
    });
  });
  tearDown(() => ChatService.sendGap = Duration.zero);

  test(
    'every message is published together with the sender\'s send clock',
    () async {
      await alice.sendText(chatId, 'one');
      final clock = await db.doc('users/alice/limits/send').get();
      expect(clock.exists, isTrue);
      expect(clock.data()!.keys, ['at']);
      expect(clock.data()!['at'], isNotNull);
    },
  );

  test(
    'sends are spaced out so the server\'s 500 ms rule is never hit',
    () async {
      ChatService.sendGap = const Duration(milliseconds: 300);
      final sw = Stopwatch()..start();
      await alice.sendText(chatId, 'one');
      final afterFirst = sw.elapsedMilliseconds;
      await alice.sendText(chatId, 'two');
      await alice.sendText(chatId, 'three');
      expect(afterFirst, lessThan(250)); // the first send never waits
      expect(
        sw.elapsedMilliseconds,
        greaterThanOrEqualTo(560),
      ); // two gaps of ~300 ms
    },
  );

  test('the chat list timestamp is not rewritten for every message', () async {
    final before = (await db.doc('chats/$chatId').get())
        .data()!['lastMessageAt'];
    await alice.sendText(chatId, 'one');
    await alice.sendText(chatId, 'two');
    final after = (await db.doc('chats/$chatId').get())
        .data()!['lastMessageAt'];
    expect(after, before); // activity was within the last minute
    // an old chat does get bumped, once
    await db.doc('chats/$chatId').update({
      'lastMessageAt': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(hours: 2)),
      ),
    });
    await alice.sendText(chatId, 'three');
    final bumped =
        (await db.doc('chats/$chatId').get()).data()!['lastMessageAt']
            as Timestamp;
    expect(
      DateTime.now().difference(bumped.toDate()),
      lessThan(const Duration(minutes: 1)),
    );
  });
}

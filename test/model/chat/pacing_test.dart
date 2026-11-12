import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/chat/chat_tuning.dart';
import 'package:flutter_test/flutter_test.dart';

FirebaseException refusal() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

void main() {
  late FakeFirebaseFirestore db;
  late ChatService alice;
  const chatId = 'alice_bob';
  // Decides each publish attempt: true lets it commit, false refuses it as
  // the server's rules would.
  late bool Function(int attempt) accept;
  var attempts = 0;

  setUp(() async {
    db = FakeFirebaseFirestore();
    attempts = 0;
    accept = (_) => true;
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
        commitBatch: (batch) {
          attempts++;
          return accept(attempts) ? batch.commit() : Future.error(refusal());
        },
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
  tearDown(() {
    ChatTuning.pacing = false;
    ChatTuning.sendBurst = 20;
    ChatTuning.sendWindow = const Duration(seconds: 10);
    ChatTuning.legacySendGap = const Duration(milliseconds: 700);
  });

  Future<Map<String, dynamic>> clock() async =>
      (await db.doc('users/alice/limits/send').get()).data()!;

  test(
    'the first message opens a window and the next ones count in it',
    () async {
      await alice.sendText(chatId, 'one');
      final opened = await clock();
      expect(opened.keys.toSet(), {'at', 'window', 'sent'});
      expect(opened['sent'], 1);
      await alice.sendText(chatId, 'two');
      await alice.sendText(chatId, 'three');
      final now = await clock();
      expect(now['sent'], 3);
      expect(now['window'], opened['window'], reason: 'the same window');
    },
  );

  test('a wrong guess is corrected at once by the other form', () async {
    ChatTuning.pacing = true;
    // Another device of this account opened a window a moment ago.
    await db.doc('users/alice/limits/send').set({
      'at': Timestamp.now(),
      'window': Timestamp.now(),
      'sent': 4,
    });
    accept = (attempt) => attempt != 1; // the server refuses a second window
    await alice.sendText(chatId, 'hi');
    expect(attempts, 2);
    expect((await clock())['sent'], 5, reason: 'counted in that window');
  });

  test(
    'a server still on the older rule gets the older form from then on',
    () async {
      ChatTuning.pacing = true;
      ChatTuning.legacySendGap = const Duration(milliseconds: 10);
      accept = (attempt) => attempt > 2; // both window forms are refused
      await alice.sendText(chatId, 'one');
      expect(attempts, 3);
      expect((await clock()).keys, ['at']);
      await alice.sendText(chatId, 'two');
      expect(attempts, 4, reason: 'no window form tried again');
      expect((await clock()).keys, ['at']);
    },
  );

  test(
    'a refusal for another reason fails every form and publishes nothing',
    () async {
      ChatTuning.pacing = true;
      ChatTuning.legacySendGap = const Duration(milliseconds: 10);
      accept = (_) => false;
      await expectLater(
        alice.sendText(chatId, 'blocked'),
        throwsA(isA<ChatException>()),
      );
      expect(attempts, 3);
      expect(
        (await db.collection('chats/$chatId/messages').get()).docs,
        isEmpty,
      );
    },
  );

  test('a burst goes out without waiting', () async {
    ChatTuning.pacing = true;
    final sw = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      await alice.sendText(chatId, 'quick $i');
    }
    // The older rule needed at least four gaps of 700 ms here.
    expect(sw.elapsed, lessThan(const Duration(milliseconds: 2800)));
  }, tags: 'timing');

  test(
    'once a burst is used up, the next message waits for the window to end',
    () async {
      ChatTuning.pacing = true;
      ChatTuning.sendBurst = 2;
      ChatTuning.sendWindow = const Duration(milliseconds: 1500);
      final sw = Stopwatch()..start();
      await alice.sendText(chatId, 'one');
      await alice.sendText(chatId, 'two');
      expect(sw.elapsed, lessThan(const Duration(milliseconds: 1500)));
      await alice.sendText(chatId, 'three');
      expect(
        sw.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 1500)),
      );
      expect((await clock())['sent'], 1, reason: 'a new window');
    },
    tags: 'timing',
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

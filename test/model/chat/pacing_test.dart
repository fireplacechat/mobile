import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/chat/chat_tuning.dart';
import 'package:flutter_test/flutter_test.dart';

var refusalCode = 'permission-denied';
FirebaseException refusal() =>
    FirebaseException(plugin: 'cloud_firestore', code: refusalCode);

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
    refusalCode = 'permission-denied';
    ChatTuning.refusalRetries = const [Duration.zero, Duration.zero];
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
    ChatTuning.sendDailyCap = 2000;
    ChatTuning.refusalRetries = const [
      Duration(milliseconds: 300),
      Duration(seconds: 1),
    ];
  });

  Future<Map<String, dynamic>> clock() async =>
      (await db.doc('users/alice/limits/send').get()).data()!;

  // A day that runs and a window that ended, as after earlier messages.
  Future<void> seedClock() => db.doc('users/alice/limits/send').set({
    'at': Timestamp.fromDate(
      DateTime.now().subtract(const Duration(seconds: 20)),
    ),
    'window': Timestamp.fromDate(
      DateTime.now().subtract(const Duration(seconds: 20)),
    ),
    'sent': 3,
    'day': Timestamp.fromDate(
      DateTime.now().subtract(const Duration(hours: 1)),
    ),
    'today': 3,
  });

  test('the first message opens a day and the next ones count in it', () async {
    await alice.sendText(chatId, 'one');
    final opened = await clock();
    expect(opened.keys.toSet(), {'at', 'window', 'sent', 'day', 'today'});
    expect(opened['sent'], 1);
    expect(opened['today'], 1);
    await alice.sendText(chatId, 'two');
    await alice.sendText(chatId, 'three');
    final now = await clock();
    expect(now['sent'], 3);
    expect(now['today'], 3);
    expect(now['window'], opened['window'], reason: 'the same window');
    expect(now['day'], opened['day'], reason: 'the same day');
  });

  test(
    'at this device\'s daily cap a send stops before anything is sent',
    () async {
      ChatTuning.sendDailyCap = 2;
      await alice.sendText(chatId, 'one');
      await alice.sendText(chatId, 'two');
      await expectLater(
        alice.sendText(chatId, 'three'),
        throwsA(
          isA<ChatException>().having(
            (e) => e.message,
            'message',
            contains('most messages allowed in a day'),
          ),
        ),
      );
      expect(attempts, 2, reason: 'nothing published for the third');
    },
  );

  test('a wrong guess is corrected at once by another form', () async {
    ChatTuning.pacing = true;
    // Another device of this account opened a day a moment ago.
    await db.doc('users/alice/limits/send').set({
      'at': Timestamp.now(),
      'window': Timestamp.now(),
      'sent': 4,
      'day': Timestamp.now(),
      'today': 4,
    });
    // The rules refuse a second day, and a new day or window while one runs.
    accept = (attempt) => attempt > 3;
    await alice.sendText(chatId, 'hi');
    expect(attempts, 4);
    expect((await clock())['today'], 5, reason: 'counted in that day');
    expect((await clock())['sent'], 5, reason: 'and in that window');
  });

  test('refused in three forms, the fourth sends it', () async {
    ChatTuning.pacing = true;
    await seedClock();
    accept = (attempt) => attempt > 3;
    await alice.sendText(chatId, 'one');
    expect(attempts, 4);
    expect(
      (await db.collection('chats/$chatId/messages').get()).docs,
      hasLength(1),
    );
  });

  test('refused in every form, it tries again and is sent', () async {
    // The window ended during the attempts, or the sign-in token was being
    // refreshed: "Send again" a moment later always worked.
    ChatTuning.pacing = true;
    await seedClock();
    accept = (attempt) => attempt > 6;
    await alice.sendText(chatId, 'patient');
    expect(attempts, 7, reason: 'the second round');
    expect(
      (await db.collection('chats/$chatId/messages').get()).docs,
      hasLength(1),
    );
  });

  test('a sign-in token being refreshed is waited out', () async {
    ChatTuning.pacing = true;
    refusalCode = 'unauthenticated';
    accept = (attempt) => attempt > 4;
    await alice.sendText(chatId, 'after refresh');
    expect(attempts, 5);
  });

  test(
    'a refusal that lasts fails every round and publishes nothing',
    () async {
      ChatTuning.pacing = true;
      accept = (_) => false;
      await expectLater(
        alice.sendText(chatId, 'blocked'),
        throwsA(isA<ChatException>()),
      );
      expect(attempts, 12, reason: 'four forms, three rounds');
      expect(
        (await db.collection('chats/$chatId/messages').get()).docs,
        isEmpty,
      );
    },
  );

  test('a refusal that cannot pass is not tried again', () async {
    ChatTuning.pacing = true;
    refusalCode = 'invalid-argument';
    accept = (_) => false;
    await expectLater(
      alice.sendText(chatId, 'too big'),
      throwsA(isA<SendRefusedException>()),
    );
    expect(attempts, 1);
  });

  test('an unknown outcome is never sent again by itself', () async {
    ChatTuning.pacing = true;
    refusalCode = 'unavailable'; // the message may have reached the server
    accept = (_) => false;
    await expectLater(
      alice.sendText(chatId, 'maybe'),
      throwsA(isA<SendNotConfirmedException>()),
    );
    expect(attempts, 1);
  });

  test('messages keep their order while one is retried', () async {
    ChatTuning.pacing = true;
    accept = (attempt) => attempt > 5;
    await Future.wait([
      alice.sendText(chatId, 'first'),
      alice.sendText(chatId, 'second'),
    ]);
    final bodies = [
      for (final m in await alice.watchMessages(chatId).first) m.body,
    ];
    expect(bodies, ['first', 'second']);
  });

  test('a burst goes out without waiting', () async {
    ChatTuning.pacing = true;
    final sw = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      await alice.sendText(chatId, 'quick $i');
    }
    // A fixed gap of 700 ms, as before decision 0028, would need 2.8 s.
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
      final now = await clock();
      expect(now['sent'], 1, reason: 'a new window');
      expect(now['today'], 3, reason: 'in the same day');
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

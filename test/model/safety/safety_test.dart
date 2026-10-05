import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

class Phone {
  Phone(this.db, this.uid) : secrets = MemorySecretStore();
  final FakeFirebaseFirestore db;
  final String uid;
  final MemorySecretStore secrets;
  final messages = MemoryMessageStore();
  late final KeyService keys;
  late final LocalDevice device;
  late final SafetyService safety;
  late final ChatService chat;
  StreamSubscription<void>? sub;

  static Future<Phone> create(FakeFirebaseFirestore db, String uid) async {
    final p = Phone(db, uid);
    p.keys = KeyService(db, p.secrets);
    p.device = await p.keys.ensureDevice(uid);
    final prekeys = PreKeyService(db, p.secrets);
    await prekeys.maintain(uid, p.device);
    p.safety = SafetyService(db, p.secrets, uid);
    await p.safety.start();
    p.chat = ChatService(
      db: db,
      uid: uid,
      device: p.device,
      keys: p.keys,
      prekeys: prekeys,
      secrets: p.secrets,
      messages: p.messages,
      safety: p.safety,
    );
    return p;
  }

  Future<List<String>> bodies(String chatId) async =>
      (await messages.watch(chatId).first).map((m) => m.body).toList();
}

Future<void> eventually(Future<bool> Function() cond, String why) async {
  for (var i = 0; i < 100; i++) {
    if (await cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  fail('timed out: $why');
}

Future<void> addUser(FakeFirebaseFirestore db, String uid) async {
  await db.collection('usernames').doc(uid).set({'uid': uid});
  await db.collection('users').doc(uid).set({'username': uid});
}

void main() {
  late FakeFirebaseFirestore db;
  late Phone alice, bob;
  const chatId = 'alice_bob';
  setUp(() async {
    db = FakeFirebaseFirestore();
    await addUser(db, 'alice');
    await addUser(db, 'bob');
    alice = await Phone.create(db, 'alice');
    bob = await Phone.create(db, 'bob');
  });
  tearDown(() async {
    await alice.sub?.cancel();
    await bob.sub?.cancel();
  });

  group('message requests', () {
    test('a new chat is an unaccepted request from its initiator', () async {
      await alice.chat.startChat('bob');
      final d = (await db.collection('chats').doc(chatId).get()).data()!;
      expect(d['initiator'], 'alice');
      expect(d['accepted'], false);
      expect(d['requestCount'], 0);
      final forBob = (await bob.chat.watchChats().first).single;
      expect(forBob.isIncomingRequest('bob'), isTrue);
      final forAlice = (await alice.chat.watchChats().first).single;
      expect(forAlice.isIncomingRequest('alice'), isFalse);
    });

    test('the initiator can send three messages, then must wait', () async {
      await alice.chat.startChat('bob');
      for (var i = 1; i <= 3; i++) {
        await alice.chat.sendText(chatId, 'request $i');
      }
      await expectLater(
        alice.chat.sendText(chatId, 'request 4'),
        throwsA(isA<ChatException>()),
      );
      final d = (await db.collection('chats').doc(chatId).get()).data()!;
      expect(d['requestCount'], 3);
      expect(
        (await db.collection('chats/$chatId/messages').get()).docs,
        hasLength(3),
      );
      // nothing was published or consumed by the refused send
      expect(await alice.bodies(chatId), [
        'request 1',
        'request 2',
        'request 3',
      ]);
    });

    test('accepting lifts the limit and the messages arrive', () async {
      await alice.chat.startChat('bob');
      for (var i = 1; i <= 3; i++) {
        await alice.chat.sendText(chatId, 'request $i');
      }
      await bob.chat.acceptRequest(chatId);
      expect(
        (await db.collection('chats').doc(chatId).get()).data()!['accepted'],
        true,
      );
      bob.sub = bob.chat.startSync(chatId);
      await eventually(
        () async => (await bob.bodies(chatId)).contains('request 3'),
        'requests delivered after accepting',
      );
      for (var i = 0; i < 6; i++) {
        await alice.chat.sendText(chatId, 'free $i');
      }
      await eventually(
        () async => (await bob.bodies(chatId)).contains('free 5'),
        'free messaging after acceptance',
      );
    });

    test('replying to a request accepts it', () async {
      await alice.chat.startChat('bob');
      await alice.chat.sendText(chatId, 'hello?');
      bob.sub = bob.chat.startSync(chatId);
      await eventually(
        () async => (await bob.bodies(chatId)).contains('hello?'),
        'delivered',
      );
      await bob.chat.sendText(chatId, 'hi alice');
      expect(
        (await db.collection('chats').doc(chatId).get()).data()!['accepted'],
        true,
      );
    });

    test('chats created before requests existed behave as accepted', () async {
      await db.collection('chats').doc(chatId).set({
        'participants': ['alice', 'bob'],
      });
      for (var i = 0; i < 5; i++) {
        await alice.chat.sendText(chatId, 'legacy $i');
      }
      final s = (await alice.chat.watchChats().first).single;
      expect(s.accepted, isTrue);
      expect(s.initiator, isNull);
      expect(s.isIncomingRequest('alice'), isFalse);
    });
  });

  group('blocking', () {
    test(
      'blocking stops you sending or starting chats, unblocking restores it',
      () async {
        await alice.chat.startChat('bob');
        await bob.chat.acceptRequest(chatId);
        await alice.chat.sendText(chatId, 'before');
        await alice.safety.block('bob');
        expect(alice.safety.isBlocked('bob'), isTrue);
        await expectLater(
          alice.chat.sendText(chatId, 'after block'),
          throwsA(isA<ChatException>()),
        );
        await expectLater(
          alice.chat.startChat('bob'),
          throwsA(isA<ChatException>()),
        );
        expect((await db.doc('users/alice/blocks/bob').get()).exists, isTrue);
        await alice.safety.unblock('bob');
        await alice.chat.sendText(chatId, 'after unblock');
        expect(await alice.bodies(chatId), ['before', 'after unblock']);
      },
    );

    test('messages from a blocked person are ignored, later ones work again after unblocking', () async {
      await alice.chat.startChat('bob');
      await bob.chat.acceptRequest(chatId);
      alice.sub = alice.chat.startSync(chatId);
      await bob.chat.sendText(chatId, 'hello alice');
      await eventually(
        () async => (await alice.bodies(chatId)).contains('hello alice'),
        'first delivery',
      );
      await alice.safety.block('bob');
      await bob.chat.sendText(chatId, 'while blocked');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(await alice.bodies(chatId), ['hello alice']);
      await alice.safety.unblock('bob');
      await bob.chat.sendText(chatId, 'after unblock');
      await eventually(
        () async => (await alice.bodies(chatId)).contains('after unblock'),
        'resumes after unblock',
      );
    });

    test(
      'the block list is observable and survives a restart of the service',
      () async {
        await alice.safety.block('bob');
        final seen = await alice.safety.watchBlocked().first;
        expect(seen, {'bob'});
        final again = SafetyService(db, alice.secrets, 'alice');
        await again.start();
        expect(again.isBlocked('bob'), isTrue);
        await again.dispose();
      },
    );
  });

  group('reporting and hiding', () {
    test(
      'a report is stored under a deterministic id with trimmed content',
      () async {
        await alice.safety.report(
          peerUid: 'bob',
          reason: ReportReason.spam,
          chatId: chatId,
          note: '  unsolicited links  ',
          context: List.generate(30, (i) => 'line $i ${'x' * 2000}'),
        );
        final d = (await db.collection('reports').doc('alice_bob').get())
            .data()!;
        expect(d['reporter'], 'alice');
        expect(d['reported'], 'bob');
        expect(d['reason'], 'spam');
        expect(d['note'], 'unsolicited links');
        expect((d['context'] as List), hasLength(20));
        expect(
          (d['context'] as List).every((c) => (c as String).length <= 1000),
          isTrue,
        );
      },
    );

    test('a report without optional fields is minimal', () async {
      await alice.safety.report(peerUid: 'bob', reason: ReportReason.abuse);
      final d = (await db.collection('reports').doc('alice_bob').get()).data()!;
      expect(d.keys.toSet(), {'reporter', 'reported', 'reason', 'createdAt'});
    });

    test('hidden requests persist locally and can be restored', () async {
      await alice.safety.hideChat(chatId);
      expect(await alice.safety.hiddenChats(), {chatId});
      final again = SafetyService(db, alice.secrets, 'alice');
      expect(await again.hiddenChats(), {chatId});
      await again.unhideChat(chatId);
      expect(await again.hiddenChats(), isEmpty);
    });
  });
}

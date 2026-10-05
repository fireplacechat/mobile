import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
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
  late final ChatService chat;
  late final SafetyService safety;
  late final RecoveryService recovery;

  static Future<Phone> create(FakeFirebaseFirestore db, String uid) async {
    final p = Phone(db, uid);
    await db.collection('usernames').doc(uid).set({'uid': uid});
    await db.collection('users').doc(uid).set({
      'username': uid,
      'displayName': uid,
    });
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
    p.recovery = RecoveryService(db, p.secrets, p.keys);
    return p;
  }
}

Future<int> count(FakeFirebaseFirestore db, String path) async =>
    (await db.collection(path).get()).docs.length;

/// firebase_auth_mocks does not clear currentUser on delete(), so record the call.
// ignore: must_be_immutable
class SpyUser extends MockUser {
  SpyUser(String uid) : super(uid: uid, email: '$uid@users.fireplace.invalid');
  bool deleted = false;
  @override
  Future<void> delete() async => deleted = true;
}

void main() {
  late FakeFirebaseFirestore db;
  late Phone alice, bob;
  const chatId = 'alice_bob';

  setUp(() async {
    db = FakeFirebaseFirestore();
    alice = await Phone.create(db, 'alice');
    bob = await Phone.create(db, 'bob');
    await alice.chat.startChat('bob');
    await bob.chat.acceptRequest(chatId);
    await alice.chat.sendText(chatId, 'from alice 1');
    await alice.chat.sendText(chatId, 'from alice 2');
    await bob.chat.sendText(chatId, 'from bob');
    await alice.recovery.createBackup('alice', alice.device.identity);
    await alice.safety.block('carol');
    await db.doc('users/alice/limits/send').set({'at': Timestamp.now()});
    await db
        .collection('users/alice/pushTokens')
        .doc(alice.device.keys.deviceId)
        .set({'token': 'fcm-token-0123456789abcdef', 'platform': 'ios'});
    await db.collection('users/alice/linkRequests').doc('newdevice-0001').set({
      'x25519Pub': 'a',
      'kemPub': 'b',
    });
    await alice.safety.report(peerUid: 'bob', reason: ReportReason.spam);
    await bob.safety.report(peerUid: 'alice', reason: ReportReason.other);
  });

  AccountService serviceFor(
    MockFirebaseAuth auth,
    Phone p, {
    void Function(String)? onStep,
    Future<void> Function(User, String)? reauth,
    List<String>? log,
  }) => AccountService(
    auth: auth,
    db: db,
    secrets: p.secrets,
    stopSession: () async => log?.add('stop'),
    destroyLocalData: () async => log?.add('destroyLocal'),
    reauthenticate: reauth ?? (_, _) async {},
    onStep: onStep,
  );

  final spies = <MockFirebaseAuth, SpyUser>{};
  MockFirebaseAuth signedInAs(String uid) {
    final user = SpyUser(uid);
    final auth = MockFirebaseAuth(signedIn: true, mockUser: user);
    spies[auth] = user;
    return auth;
  }

  test('deletes everything personal, keeps what belongs to others', () async {
    final auth = signedInAs('alice');
    final log = <String>[];
    await serviceFor(
      auth,
      alice,
      log: log,
    ).deleteAccount(password: 'correct horse');

    // account data
    expect((await db.collection('users').doc('alice').get()).exists, isFalse);
    expect(
      (await db.collection('usernames').doc('alice').get()).exists,
      isFalse,
    );
    expect(await count(db, 'users/alice/devices'), 0);
    expect(await count(db, 'users/alice/private'), 0);
    expect(await count(db, 'users/alice/linkRequests'), 0);
    expect(await count(db, 'users/alice/blocks'), 0);
    expect(await count(db, 'users/alice/limits'), 0);
    expect(await count(db, 'users/alice/pushTokens'), 0);
    // prekeys under the deleted device are gone as well
    final devId = alice.device.keys.deviceId;
    expect(await count(db, 'users/alice/devices/$devId/prekeys'), 0);
    // her messages are gone, bob's remain, the chat document remains for bob to tidy up
    final msgs = (await db.collection('chats/$chatId/messages').get()).docs;
    expect(msgs.map((d) => d.data()['senderUid']), ['bob']);
    expect((await db.collection('chats').doc(chatId).get()).exists, isTrue);
    // others untouched
    expect((await db.collection('users').doc('bob').get()).exists, isTrue);
    expect(await count(db, 'users/bob/devices'), 1);
    // reports are kept
    expect(await count(db, 'reports'), 2);
    // local erase + session stop happened, secrets are empty, auth user removed
    expect(log, ['stop', 'destroyLocal']);
    expect(alice.secrets.data, isEmpty);
    expect(spies[auth]!.deleted, isTrue);
  });

  test('wrong password: nothing is deleted', () async {
    final auth = signedInAs('alice');
    final svc = serviceFor(
      auth,
      alice,
      reauth: (_, _) async =>
          throw FirebaseAuthException(code: 'wrong-password'),
    );
    await expectLater(
      svc.deleteAccount(password: 'nope'),
      throwsA(isA<AuthException>()),
    );
    expect((await db.collection('users').doc('alice').get()).exists, isTrue);
    expect(await count(db, 'users/alice/devices'), 1);
    expect(alice.secrets.data, isNotEmpty);
    expect(spies[auth]!.deleted, isFalse);
    expect(
      (await db.collection('users').doc('alice').get()).data()!.containsKey(
        'deleting',
      ),
      isFalse,
    );
  });

  test('not signed in is refused', () async {
    await expectLater(
      serviceFor(MockFirebaseAuth(), alice).deleteAccount(password: 'x'),
      throwsA(isA<AuthException>()),
    );
  });

  test('an interrupted deletion leaves a flag and can be finished', () async {
    final auth = signedInAs('alice');
    await expectLater(
      serviceFor(
        auth,
        alice,
        onStep: (s) {
          if (s == 'profile') throw StateError('network dropped');
        },
      ).deleteAccount(password: 'pw'),
      throwsStateError,
    );
    // devices already gone, profile flagged so the app resumes deletion
    expect(await count(db, 'users/alice/devices'), 0);
    final profile = (await db.collection('users').doc('alice').get()).data()!;
    expect(profile['deleting'], true);
    expect(spies[auth]!.deleted, isFalse);
    // second attempt (any number of steps already done) completes
    await serviceFor(auth, alice).deleteAccount(password: 'pw');
    expect((await db.collection('users').doc('alice').get()).exists, isFalse);
    expect(
      (await db.collection('usernames').doc('alice').get()).exists,
      isFalse,
    );
    expect(spies[auth]!.deleted, isTrue);
  });

  test(
    'a half-deleted account (profile already gone) can still be finished',
    () async {
      final auth = signedInAs('alice');
      await db.collection('users').doc('alice').delete();
      await serviceFor(auth, alice).deleteAccount(password: 'pw');
      expect(await count(db, 'users/alice/devices'), 0);
      expect(
        (await db.collection('chats/$chatId/messages').get()).docs.map(
          (d) => d.data()['senderUid'],
        ),
        ['bob'],
      );
      expect(spies[auth]!.deleted, isTrue);
    },
  );

  test('steps run in the documented order', () async {
    final seen = <String>[];
    await serviceFor(
      signedInAs('alice'),
      alice,
      onStep: seen.add,
    ).deleteAccount(password: 'pw');
    expect(seen, AccountService.steps);
  });

  group('the other person cleans up', () {
    test('a conversation with a deleted account is removed', () async {
      await serviceFor(
        signedInAs('alice'),
        alice,
      ).deleteAccount(password: 'pw');
      expect(await bob.chat.removeChatIfPeerDeleted(chatId), isTrue);
      expect((await db.collection('chats').doc(chatId).get()).exists, isFalse);
      expect(await count(db, 'chats/$chatId/messages'), 0);
      expect((await bob.messages.watch(chatId).first), isEmpty);
    });

    test('nothing is removed while the other account exists', () async {
      expect(await bob.chat.removeChatIfPeerDeleted(chatId), isFalse);
      expect((await db.collection('chats').doc(chatId).get()).exists, isTrue);
      expect(await count(db, 'chats/$chatId/messages'), 3);
    });

    test('a deleted contact cannot be messaged and shows no devices', () async {
      await serviceFor(
        signedInAs('alice'),
        alice,
      ).deleteAccount(password: 'pw');
      await expectLater(
        bob.chat.sendText(chatId, 'hello?'),
        throwsA(isA<ChatException>()),
      );
    });
  });
}

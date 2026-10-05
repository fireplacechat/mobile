import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

/// One simulated device: its own secret store, local history and services.
class Dev {
  Dev(this.db, this.uid, this.secrets, this.keys, this.messages);
  final FakeFirebaseFirestore db;
  final String uid;
  final MemorySecretStore secrets;
  final KeyService keys;
  final MemoryMessageStore messages;
  late ChatService chat;
  final subs = <StreamSubscription<void>>[];

  static Future<Dev> create(FakeFirebaseFirestore db, String uid) async {
    final secrets = MemorySecretStore();
    final d = Dev(
      db,
      uid,
      secrets,
      KeyService(db, secrets),
      MemoryMessageStore(),
    );
    await d._init(await d.keys.ensureDevice(uid));
    return d;
  }

  /// Another device of an account that already has an identity (stand-in for Phase 6 linking).
  static Future<Dev> linked(FakeFirebaseFirestore db, Dev existing) async {
    final secrets = MemorySecretStore();
    final identity = (await existing.keys.ensureDevice(existing.uid)).identity;
    final dk = await DeviceKeys.generate();
    final bundle = await dk.certify(identity, existing.uid);
    await db
        .collection('users')
        .doc(existing.uid)
        .collection('devices')
        .doc(dk.deviceId)
        .set({
          ...bundle.toFirestore(),
          'createdAt': FieldValue.serverTimestamp(),
        });
    final d = Dev(
      db,
      existing.uid,
      secrets,
      KeyService(db, secrets),
      MemoryMessageStore(),
    );
    await d._init(LocalDevice(identity, dk, bundle));
    return d;
  }

  Future<void> _init(LocalDevice ld) async {
    chat = ChatService(
      db: db,
      uid: uid,
      device: ld,
      keys: keys,
      prekeys: PreKeyService(db, secrets),
      secrets: secrets,
      messages: messages,
    );
    await PreKeyService(db, secrets).maintain(uid, ld);
  }

  Future<List<LocalMessage>> history(String chatId) =>
      messages.watch(chatId).first;
  void sync(String chatId) => subs.add(chat.startSync(chatId));
  Future<void> close() async {
    for (final s in subs) {
      await s.cancel();
    }
  }
}

Future<void> eventually(Future<bool> Function() cond, {String? why}) async {
  for (var i = 0; i < 100; i++) {
    if (await cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  fail('condition not met: ${why ?? ''}');
}

Future<bool> hasBodies(Dev d, String chatId, List<String> bodies) async {
  final h = (await d.history(chatId)).map((m) => m.body).toList();
  return bodies.every(h.contains);
}

/// Every string anywhere in Firestore, to prove no plaintext leaks.
Future<String> dumpFirestore(FakeFirebaseFirestore db) async => db.dump();

Future<void> addUser(FakeFirebaseFirestore db, String uid, String name) async {
  await db.collection('usernames').doc(name).set({'uid': uid});
  await db.collection('users').doc(uid).set({
    'username': name,
    'displayName': name,
  });
}

class _SuspendedAuth extends MockFirebaseAuth {
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async => throw FirebaseAuthException(code: 'user-disabled');
}

void main() {
  group('AuthService', () {
    test('username validation and email mapping', () {
      expect(AuthService.isValidUsername('Alice_01'), isTrue); // normalized
      expect(AuthService.isValidUsername('ab'), isFalse);
      expect(AuthService.isValidUsername('bad name'), isFalse);
      expect(AuthService.emailFor(' Alice '), 'alice@users.fireplace.invalid');
    });

    test('a suspended account gets a clear message on sign-in', () async {
      final auth = AuthService(_SuspendedAuth(), FakeFirebaseFirestore());
      await expectLater(
        auth.signIn(username: 'troll', password: 'whatever123'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('suspended'),
          ),
        ),
      );
    });

    test(
      'invite codes: normalization and the hash shared with the operator tool',
      () async {
        expect(
          AuthService.normalizeInvite('abcd-efgh jklm-npqr'),
          'ABCDEFGHJKLMNPQR',
        );
        for (final bad in [
          '',
          'ABCD',
          'ABCD-EFGH-JKLM-NPQ1',
          'ABCD-EFGH-JKLM-NPQRS',
          'abcd efgh jklm npq!',
        ]) {
          expect(AuthService.normalizeInvite(bad), isNull, reason: bad);
        }
        // Same value the Node operator tool computes (tools/operator/test/invites.test.js).
        expect(
          await AuthService.inviteHash('ABCDEFGHJKLMNPQR'),
          '7cf629bb82226bfb6356859edb341b8f36a74d8997c4fe385dbef6dc85c5c4bb',
        );
      },
    );

    test('signUp creates username + profile docs and claims the invite; rejects bad input', () async {
      final db = FakeFirebaseFirestore();
      final auth = AuthService(MockFirebaseAuth(), db);
      final hash = await AuthService.inviteHash('ABCDEFGHJKLMNPQR');
      await db.collection('invites').doc(hash).set({'note': 'for alice'});
      final user = await auth.signUp(
        username: 'Alice',
        password: 'correct horse',
        inviteCode: 'abcd-efgh-jklm-npqr',
        displayName: 'Al',
      );
      expect((await db.collection('usernames').doc('alice').get()).data(), {
        'uid': user.uid,
      });
      final profile = (await db.collection('users').doc(user.uid).get())
          .data()!;
      expect(profile['username'], 'alice');
      expect(profile['displayName'], 'Al');
      expect(profile['invite'], hash);
      expect(profile.containsKey('email'), isFalse);
      final invite = (await db.collection('invites').doc(hash).get()).data()!;
      expect(invite['usedBy'], user.uid);
      expect(invite['usedAt'], isNotNull);
      expect(invite['note'], 'for alice'); // operator's note untouched
      const code = 'ABCD-EFGH-JKLM-NPQR';
      await expectLater(
        auth.signUp(username: 'x', password: 'correct horse', inviteCode: code),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        auth.signUp(username: 'carol', password: 'short', inviteCode: code),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        auth.signUp(
          username: 'carol',
          password: 'correct horse',
          inviteCode: 'nope',
        ),
        throwsA(isA<AuthException>()),
      );
      // nothing was created for the rejected attempts
      expect((await db.collection('users').get()).docs, hasLength(1));
    });

    test('a missing invite document rolls the new account back', () async {
      final db = FakeFirebaseFirestore(); // no invite exists
      final auth = MockFirebaseAuth();
      await expectLater(
        AuthService(auth, db).signUp(
          username: 'dave',
          password: 'correct horse',
          inviteCode: 'ABCD-EFGH-JKLM-NPQR',
        ),
        throwsA(isA<AuthException>()),
      );
      // (Real Firestore batches are atomic, so nothing is left behind; the fake
      // does not roll back, so that part is covered by the rules tests.)
    });
  });

  group('KeyService', () {
    test('first run generates + publishes; later runs reuse; new install needs recovery', () async {
      final db = FakeFirebaseFirestore();
      final secrets = MemorySecretStore();
      final ks = KeyService(db, secrets);
      final d1 = await ks.ensureDevice('alice');
      final d2 = await ks.ensureDevice('alice');
      expect(d2.keys.deviceId, d1.keys.deviceId);
      expect(await d2.bundle.verifyCert(), isTrue);
      final published = await db.collection('users/alice/devices').get();
      expect(published.docs.single.id, d1.keys.deviceId);
      // no private material on the server
      final dump = await dumpFirestore(db);
      expect(dump.contains(b64(d1.keys.x25519Seed)), isFalse);
      expect(dump.contains(b64(d1.keys.kemSecret)), isFalse);
      // fresh install, account already has a device
      await expectLater(
        KeyService(db, MemorySecretStore()).ensureDevice('alice'),
        throwsA(isA<NeedsRecoveryException>()),
      );
    });

    test('TOFU pin; changed identity is flagged until accepted', () async {
      final db = FakeFirebaseFirestore();
      final bob = await Dev.create(db, 'bob');
      final alice = await Dev.create(db, 'alice');
      final seen = await alice.keys.fetchDevices('bob');
      expect(seen, hasLength(1));
      // Server (or attacker) replaces bob's device with one under a different identity.
      final evilId = await AccountIdentity.generate();
      final evilKeys = await DeviceKeys.generate();
      final evil = await evilKeys.certify(evilId, 'bob');
      await db.collection('users/bob/devices').doc(evilKeys.deviceId).set({
        ...evil.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      await expectLater(
        alice.keys.fetchDevices('bob'),
        throwsA(isA<IdentityChangedException>()),
      );
      await alice.keys.acceptIdentityChange('bob', evilId.publicBytes);
      // now the original bob device is the one that mismatches
      await expectLater(
        alice.keys.fetchDevices('bob'),
        throwsA(isA<IdentityChangedException>()),
      );
      expect(bob.uid, 'bob');
    });

    test('revoked devices and invalid certificates are ignored', () async {
      final db = FakeFirebaseFirestore();
      final alice = await Dev.create(db, 'alice');
      final bob = await Dev.create(db, 'bob');
      final bobDev = (await bob.keys.ensureDevice('bob'));
      // forged doc: bob's identity but a cert made over other keys
      final k = await DeviceKeys.generate();
      await db.collection('users/bob/devices').doc(k.deviceId).set({
        'x25519Pub': b64(k.x25519Pub),
        'kemPub': b64(k.kemPub),
        'sigPub': b64(bobDev.identity.publicBytes),
        'deviceCert': b64(bobDev.bundle.cert),
        'createdAt': FieldValue.serverTimestamp(),
      });
      expect((await alice.keys.fetchDevices('bob')).map((b) => b.deviceId), [
        bobDev.keys.deviceId,
      ]);
      await db.collection('users/bob/devices').doc(bobDev.keys.deviceId).update(
        {'revokedAt': Timestamp.now()},
      );
      expect(await alice.keys.fetchDevices('bob'), isEmpty);
    });
  });

  group('Trust features', () {
    test(
      'verification binds to the pinned identity and resets on identity change',
      () async {
        final db = FakeFirebaseFirestore();
        final alice = await Dev.create(db, 'alice');
        final bob = await Dev.create(db, 'bob');
        await alice.keys.fetchDevices('bob'); // pin
        expect(await alice.keys.isVerified('bob'), isFalse);
        final bobId = (await bob.keys.ensureDevice('bob')).identity.publicBytes;
        await alice.keys.markVerified('bob', bobId);
        expect(await alice.keys.isVerified('bob'), isTrue);
        final other = await AccountIdentity.generate();
        await alice.keys.acceptIdentityChange('bob', other.publicBytes);
        expect(await alice.keys.isVerified('bob'), isFalse);
      },
    );

    test('new peer devices are detected once, first sight is silent', () async {
      final db = FakeFirebaseFirestore();
      final alice = await Dev.create(db, 'alice');
      final bob = await Dev.create(db, 'bob');
      expect(await alice.keys.detectNewDevices('bob'), isEmpty);
      expect(await alice.keys.detectNewDevices('bob'), isEmpty);
      final bob2 = await Dev.linked(db, bob);
      final bobFirst = (await bob.keys.ensureDevice('bob')).keys.deviceId;
      final id2 = (await db.collection('users/bob/devices').get()).docs
          .map((d) => d.id)
          .where((i) => i != bobFirst);
      expect(await alice.keys.detectNewDevices('bob'), id2.toList());
      expect(await alice.keys.detectNewDevices('bob'), isEmpty);
      expect(bob2.uid, 'bob');
    });

    test('list and revoke own devices; revoked device is not used and learns it was revoked', () async {
      final db = FakeFirebaseFirestore();
      final a1 = await Dev.create(db, 'alice');
      final a2 = await Dev.linked(db, a1);
      final ld1 = await a1.keys.ensureDevice('alice');
      final list = await a1.keys.listOwnDevices('alice', ld1.keys.deviceId);
      expect(list, hasLength(2));
      expect(list.where((d) => d.isThisDevice), hasLength(1));
      final other = list.firstWhere((d) => !d.isThisDevice);
      await expectLater(
        a1.keys.revokeDevice(
          'alice',
          ld1.keys.deviceId,
          thisDeviceId: ld1.keys.deviceId,
        ),
        throwsStateError,
      );
      await a1.keys.revokeDevice(
        'alice',
        other.deviceId,
        thisDeviceId: ld1.keys.deviceId,
      );
      expect(
        (await a1.keys.listOwnDevices(
          'alice',
          ld1.keys.deviceId,
        )).where((d) => d.revoked),
        hasLength(1),
      );
      expect((await a1.keys.fetchDevices('alice')).map((d) => d.deviceId), [
        ld1.keys.deviceId,
      ]);
      expect(a2.uid, 'alice');
    });

    test('a revoked device cannot start up again', () async {
      final db = FakeFirebaseFirestore();
      final secrets = MemorySecretStore();
      final ks = KeyService(db, secrets);
      final d = await ks.ensureDevice('alice');
      await db.collection('users/alice/devices').doc(d.keys.deviceId).update({
        'revokedAt': Timestamp.now(),
      });
      await expectLater(
        ks.ensureDevice('alice'),
        throwsA(isA<DeviceRevokedException>()),
      );
    });

    test('verify payload round trip and rejection of junk', () {
      final n = List.generate(12, (i) => '${10000 + i}').join(' ');
      final p = VerifyPayload.fromSafetyNumber(n);
      expect(VerifyPayload.parse(p.encode())!.matches(n), isTrue);
      expect(
        VerifyPayload.parse(p.encode())!.matches(n.replaceFirst('1', '2')),
        isFalse,
      );
      for (final junk in [
        null,
        '',
        'https://evil.example',
        'fireplace://verify/1/123',
        'fireplace://verify/2/${'1' * 60}',
      ]) {
        expect(VerifyPayload.parse(junk), isNull);
      }
    });
  });

  group('ChatService', () {
    late FakeFirebaseFirestore db;
    late Dev alice, bob;
    late String chatId;

    setUp(() async {
      db = FakeFirebaseFirestore();
      await addUser(db, 'alice', 'alice');
      await addUser(db, 'bob', 'bob');
      alice = await Dev.create(db, 'alice');
      bob = await Dev.create(db, 'bob');
      chatId = await alice.chat.startChat('Bob');
    });
    tearDown(() async {
      await alice.close();
      await bob.close();
    });

    test(
      'startChat is canonical and idempotent; errors for unknown/self',
      () async {
        expect(chatId, 'alice_bob');
        expect(await bob.chat.startChat('alice'), chatId);
        expect((await db.collection('chats').get()).docs, hasLength(1));
        await expectLater(
          alice.chat.startChat('nobody'),
          throwsA(isA<ChatException>()),
        );
        await expectLater(
          alice.chat.startChat('alice'),
          throwsA(isA<ChatException>()),
        );
      },
    );

    test('end to end: both directions, server sees only ciphertext', () async {
      bob.sync(chatId);
      alice.sync(chatId);
      await alice.chat.sendText(chatId, 'hello bob, the eagle has landed');
      await eventually(
        () => hasBodies(bob, chatId, ['hello bob, the eagle has landed']),
      );
      await bob.chat.sendText(chatId, 'roger that alice');
      await eventually(() => hasBodies(alice, chatId, ['roger that alice']));
      await alice.chat.sendText(chatId, 'second message');
      await eventually(() => hasBodies(bob, chatId, ['second message']));

      final dump = await dumpFirestore(db);
      expect(
        dump.contains('senderUid'),
        isTrue,
        reason: 'dump must actually contain messages',
      );
      for (final secret in ['eagle', 'roger that', 'second message']) {
        expect(dump.contains(secret), isFalse, reason: secret);
      }
      final msgs = await db.collection('chats/$chatId/messages').get();
      expect(msgs.docs, hasLength(3));
      for (final m in msgs.docs) {
        expect(m.data().keys.toSet(), {
          'senderUid',
          'senderDevice',
          'ts',
          'envelopes',
          'expireAt',
        });
        // Retention: the server copy expires about 30 days after it was sent.
        final days =
            (m.data()['expireAt'] as Timestamp)
                .toDate()
                .difference(DateTime.now())
                .inHours /
            24;
        expect(days, inInclusiveRange(29.5, 30.1));
      }
      final h = await bob.history(chatId);
      expect(h.where((m) => m.outgoing).map((m) => m.body), [
        'roger that alice',
      ]);
      expect(h.every((m) => m.status == MessageStatus.ok), isTrue);
    });

    test(
      'messages sent while offline arrive in order after sync starts',
      () async {
        for (final t in ['one', 'two', 'three']) {
          await alice.chat.sendText(chatId, t);
        }
        bob.sync(chatId);
        await eventually(() => hasBodies(bob, chatId, ['one', 'two', 'three']));
        expect((await bob.history(chatId)).map((m) => m.body), [
          'one',
          'two',
          'three',
        ]);
      },
    );

    test(
      'each message is processed once (restart does not duplicate)',
      () async {
        bob.sync(chatId);
        await alice.chat.sendText(chatId, 'only once');
        await eventually(() => hasBodies(bob, chatId, ['only once']));
        await bob.close();
        bob.sync(chatId); // re-subscribe: same docs replay
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          (await bob.history(chatId)).where((m) => m.body == 'only once'),
          hasLength(1),
        );
      },
    );

    test('simultaneous first messages (glare) still converge', () async {
      await alice.chat.sendText(chatId, 'a-first');
      await bob.chat.sendText(chatId, 'b-first');
      alice.sync(chatId);
      bob.sync(chatId);
      await eventually(
        () => hasBodies(bob, chatId, ['a-first']),
        why: 'bob got a-first',
      );
      await eventually(
        () => hasBodies(alice, chatId, ['b-first']),
        why: 'alice got b-first',
      );
      await alice.chat.sendText(chatId, 'a-second');
      await bob.chat.sendText(chatId, 'b-second');
      await eventually(() => hasBodies(bob, chatId, ['a-second']));
      await eventually(() => hasBodies(alice, chatId, ['b-second']));
    });

    test('multi-device: all recipient devices and sender\'s other devices get the message', () async {
      final bob2 = await Dev.linked(db, bob);
      final alice2 = await Dev.linked(db, alice);
      for (final d in [alice, alice2, bob, bob2]) {
        d.sync(chatId);
      }
      await alice.chat.sendText(chatId, 'to all of bob');
      await eventually(() => hasBodies(bob, chatId, ['to all of bob']));
      await eventually(() => hasBodies(bob2, chatId, ['to all of bob']));
      await eventually(
        () => hasBodies(alice2, chatId, ['to all of bob']),
        why: 'own other device',
      );
      await bob2.chat.sendText(chatId, 'from bob2');
      await eventually(() => hasBodies(alice, chatId, ['from bob2']));
      await eventually(() => hasBodies(alice2, chatId, ['from bob2']));
      await eventually(
        () => hasBodies(bob, chatId, ['from bob2']),
        why: 'bob sees bob2',
      );
      expect(
        (await alice2.history(chatId))
            .firstWhere((m) => m.body == 'to all of bob')
            .outgoing,
        isFalse,
      );
      await bob2.close();
      await alice2.close();
    });

    test(
      'device added later cannot read earlier messages but gets a placeholder',
      () async {
        await alice.chat.sendText(chatId, 'before bob2 existed');
        final bob2 = await Dev.linked(db, bob);
        bob2.sync(chatId);
        await eventually(() async => (await bob2.history(chatId)).isNotEmpty);
        final m = (await bob2.history(chatId)).single;
        expect(m.status, MessageStatus.undecryptable);
        expect(m.body.contains('before bob2'), isFalse);
        await bob2.close();
      },
    );

    test('tampered ciphertext is stored as undecryptable, later messages still work', () async {
      await alice.chat.sendText(chatId, 'will be corrupted');
      final doc =
          (await db.collection('chats/$chatId/messages').get()).docs.single;
      final bobId = (await bob.keys.ensureDevice('bob')).keys.deviceId;
      final env = Map<String, dynamic>.from(doc.data()['envelopes'][bobId]);
      final ct = unb64(env['ct']);
      ct[0] ^= 1;
      env['ct'] = b64(ct);
      await doc.reference.update({'envelopes.$bobId': env});
      bob.sync(chatId);
      await eventually(() async => (await bob.history(chatId)).isNotEmpty);
      expect(
        (await bob.history(chatId)).single.status,
        MessageStatus.undecryptable,
      );
      await alice.chat.sendText(chatId, 'next one is fine');
      await eventually(() => hasBodies(bob, chatId, ['next one is fine']));
    });

    test('a changed contact identity blocks sending', () async {
      await alice.chat.sendText(chatId, 'ok'); // pins bob
      final evilId = await AccountIdentity.generate();
      final k = await DeviceKeys.generate();
      final b = await k.certify(evilId, 'bob');
      await db.collection('users/bob/devices').doc(k.deviceId).set({
        ...b.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      await expectLater(
        alice.chat.sendText(chatId, 'leaky'),
        throwsA(isA<IdentityChangedException>()),
      );
      expect((await dumpFirestore(db)).contains('leaky'), isFalse);
    });

    test('watchChats lists chats for the user with the peer uid', () async {
      final list = await alice.chat.watchChats().first;
      expect(list.single.peerUid, 'bob');
      expect(jsonEncode(list.single.chatId), '"alice_bob"');
    });
  });
}

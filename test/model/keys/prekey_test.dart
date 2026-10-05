import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/prekey_helpers.dart';

Future<void> eventually(Future<bool> Function() cond, String why) async {
  for (var i = 0; i < 150; i++) {
    if (await cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  fail('timed out: $why');
}

class Phone {
  Phone(this.db, this.uid, {DateTime Function()? clock})
    : secrets = MemorySecretStore() {
    keys = KeyService(db, secrets);
    prekeys = PreKeyService(db, secrets, clock: clock);
  }
  final FakeFirebaseFirestore db;
  final String uid;
  final MemorySecretStore secrets;
  final messages = MemoryMessageStore();
  late final KeyService keys;
  late final PreKeyService prekeys;
  late final LocalDevice device;
  late final ChatService chat;
  StreamSubscription<void>? sub;

  static Future<Phone> create(
    FakeFirebaseFirestore db,
    String uid, {
    DateTime Function()? clock,
    bool publishPrekeys = true,
  }) async {
    final p = Phone(db, uid, clock: clock);
    p.device = await p.keys.ensureDevice(uid);
    if (publishPrekeys) await p.prekeys.maintain(uid, p.device);
    p.chat = ChatService(
      db: db,
      uid: uid,
      device: p.device,
      keys: p.keys,
      prekeys: p.prekeys,
      secrets: p.secrets,
      messages: p.messages,
    );
    return p;
  }

  CollectionReference<Map<String, dynamic>> get prekeyCol =>
      db.collection('users/$uid/devices/${device.keys.deviceId}/prekeys');
  Future<List<String>> bodies(String chatId) async =>
      (await messages.watch(chatId).first).map((m) => m.body).toList();
}

Future<void> addUser(FakeFirebaseFirestore db, String uid) async {
  await db.collection('usernames').doc(uid).set({'uid': uid});
  await db.collection('users').doc(uid).set({'username': uid});
}

void main() {
  late FakeFirebaseFirestore db;
  const chatId = 'alice_bob';
  setUp(() async {
    db = FakeFirebaseFirestore();
    await addUser(db, 'alice');
    await addUser(db, 'bob');
  });

  group('PreKeyService.maintain', () {
    test(
      'first run publishes one signed prekey and a full one-time pool',
      () async {
        final bob = await Phone.create(db, 'bob');
        final docs = (await bob.prekeyCol.get()).docs;
        expect(docs.where((d) => d.data()['kind'] == 'signed'), hasLength(1));
        expect(
          docs.where((d) => d.data()['kind'] == 'onetime'),
          hasLength(PreKeyService.poolTarget),
        );
        // private halves never reach the server
        final dump = db.dump();
        final stored = jsonDecode(
          (await bob.secrets.read('prekeys:bob:${bob.device.keys.deviceId}'))!,
        );
        final seed = (stored['signed'] as List).first['x25519Seed'] as String;
        expect(dump.contains(seed), isFalse);
      },
    );

    test('is idempotent when nothing is due', () async {
      final bob = await Phone.create(db, 'bob');
      final before = (await bob.prekeyCol.get()).docs.map((d) => d.id).toSet();
      await bob.prekeys.maintain('bob', bob.device);
      expect((await bob.prekeyCol.get()).docs.map((d) => d.id).toSet(), before);
    });

    test('tops the pool up once it runs low', () async {
      final bob = await Phone.create(db, 'bob');
      final otps =
          (await bob.prekeyCol.where('kind', isEqualTo: 'onetime').get()).docs;
      for (final d in otps.take(11)) {
        await bob.prekeys.consumeOneTime('bob', bob.device.keys.deviceId, d.id);
      }
      expect(
        (await bob.prekeyCol.where('kind', isEqualTo: 'onetime').get()).docs,
        hasLength(9),
      );
      await bob.prekeys.maintain('bob', bob.device);
      expect(
        (await bob.prekeyCol.where('kind', isEqualTo: 'onetime').get()).docs,
        hasLength(PreKeyService.poolTarget),
      );
    });

    test('rotates the signed prekey weekly, keeps the old private half for two weeks', () async {
      var now = DateTime(2026, 1, 1);
      final bob = await Phone.create(db, 'bob', clock: () => now);
      final first =
          (await bob.prekeyCol.where('kind', isEqualTo: 'signed').get())
              .docs
              .single
              .id;
      now = now.add(const Duration(days: 8));
      await bob.prekeys.maintain('bob', bob.device);
      final second =
          (await bob.prekeyCol.where('kind', isEqualTo: 'signed').get())
              .docs
              .single
              .id;
      expect(second, isNot(first));
      // the old one is gone from the server but a handshake using it still resolves
      final hsOld = HandshakeInit(
        ek: Uint8List32(),
        kemCt: Uint8List1088(),
        spkId: first,
      );
      expect(
        await bob.prekeys.resolve('bob', bob.device.keys.deviceId, hsOld),
        isNotNull,
      );
      // after the retention window the private half is deleted (forward secrecy)
      now = now.add(const Duration(days: 20));
      await bob.prekeys.maintain('bob', bob.device);
      expect(
        await bob.prekeys.resolve('bob', bob.device.keys.deviceId, hsOld),
        isNull,
      );
    });
  });

  group('claiming', () {
    test(
      'fetchBundle returns a verified signed prekey and a one-time prekey',
      () async {
        final bob = await Phone.create(db, 'bob');
        final alice = await Phone.create(db, 'alice');
        final target = (await alice.keys.fetchDevices('bob')).single;
        final b = await alice.prekeys.fetchBundle(target);
        expect(await PreKeys.verifySigned(target, b.signed), isTrue);
        expect(b.oneTime, isNotNull);
        expect(bob.uid, 'bob');
      },
    );

    test('a forged signed prekey on the server is ignored; with none valid it fails clearly', () async {
      final bob = await Phone.create(db, 'bob');
      final alice = await Phone.create(db, 'alice');
      final target = (await alice.keys.fetchDevices('bob')).single;
      // Attacker with server access replaces the signed prekey with their own key.
      final real =
          (await bob.prekeyCol.where('kind', isEqualTo: 'signed').get())
              .docs
              .single;
      final evilId = await AccountIdentity.generate();
      final evilRec = await PreKeyRecord.generate();
      final forged = await PreKeys.sign(
        evilRec,
        evilId,
        'bob',
        bob.device.keys.deviceId,
      );
      await real.reference.delete();
      await bob.prekeyCol.doc(forged.id).set({
        ...forged.toFirestore(),
        'createdAt': Timestamp.now(),
      });
      await expectLater(
        alice.prekeys.fetchBundle(target),
        throwsA(isA<PreKeyException>()),
      );
    });

    test('malformed prekey documents are skipped', () async {
      final bob = await Phone.create(db, 'bob');
      final alice = await Phone.create(db, 'alice');
      final target = (await alice.keys.fetchDevices('bob')).single;
      await bob.prekeyCol.doc('junk-1').set({
        'kind': 'onetime',
        'x25519Pub': 5,
      });
      await bob.prekeyCol.doc('junk-2').set({'kind': 'signed'});
      for (var i = 0; i < 20; i++) {
        final b = await alice.prekeys.fetchBundle(target);
        expect(b.oneTime!.id, isNot(startsWith('junk')));
      }
    });
  });

  group('in a conversation', () {
    test('the one-time prekey is consumed (privately and on the server) after the first message', () async {
      final bob = await Phone.create(db, 'bob');
      final alice = await Phone.create(db, 'alice');
      await alice.chat.startChat('bob');
      final before =
          (await bob.prekeyCol.where('kind', isEqualTo: 'onetime').get())
              .docs
              .length;
      bob.sub = bob.chat.startSync(chatId);
      await alice.chat.sendText(chatId, 'hello');
      await eventually(
        () async => (await bob.bodies(chatId)).contains('hello'),
        'delivered',
      );
      await eventually(
        () async =>
            (await bob.prekeyCol.where('kind', isEqualTo: 'onetime').get())
                .docs
                .length ==
            before - 1,
        'opk deleted on server',
      );
      final stored = jsonDecode(
        (await bob.secrets.read('prekeys:bob:${bob.device.keys.deviceId}'))!,
      );
      expect((stored['oneTime'] as Map).length, before - 1);
      await bob.sub?.cancel();
    });

    test('works when the contact has no one-time prekeys left', () async {
      final bob = await Phone.create(db, 'bob');
      final alice = await Phone.create(db, 'alice');
      for (final d
          in (await bob.prekeyCol.where('kind', isEqualTo: 'onetime').get())
              .docs) {
        await bob.prekeys.consumeOneTime('bob', bob.device.keys.deviceId, d.id);
      }
      await alice.chat.startChat('bob');
      bob.sub = bob.chat.startSync(chatId);
      await alice.chat.sendText(chatId, 'signed prekey only');
      await eventually(
        () async => (await bob.bodies(chatId)).contains('signed prekey only'),
        'delivered',
      );
      await bob.sub?.cancel();
    });

    test('a handshake using an already consumed one-time prekey is refused, later sessions still work', () async {
      final bob = await Phone.create(db, 'bob');
      final alice = await Phone.create(db, 'alice');
      await alice.chat.startChat('bob');
      // Alice grabs a bundle, then Bob's OPK gets consumed by someone else before delivery.
      final target = (await alice.keys.fetchDevices('bob')).single;
      final bundle = await alice.prekeys.fetchBundle(target);
      await bob.prekeys.consumeOneTime(
        'bob',
        bob.device.keys.deviceId,
        bundle.oneTime!.id,
      );
      final (s, _) = await Session.initiate(
        local: alice.device.keys,
        localBundle: alice.device.bundle,
        remote: bundle,
      );
      final env = await s.encrypt(
        utf8.encode(jsonEncode({'type': 'text', 'body': 'late'})),
        chatId: chatId,
      );
      await db.collection('chats/$chatId/messages').doc('m1').set({
        'senderUid': 'alice',
        'senderDevice': alice.device.keys.deviceId,
        'ts': Timestamp.now(),
        'envelopes': {bob.device.keys.deviceId: env.toJson()},
      });
      bob.sub = bob.chat.startSync(chatId);
      await eventually(
        () async =>
            (await bob.bodies(chatId))
                .contains('Encryption key no longer available.'),
        'refused',
      );
      // a fresh send by Alice's ChatService starts a new, working session
      await alice.chat.sendText(chatId, 'second try');
      await eventually(
        () async => (await bob.bodies(chatId)).contains('second try'),
        'recovered',
      );
      await bob.sub?.cancel();
    });

    test('a contact that never published prekeys gives a clear error and nothing is published', () async {
      await Phone.create(db, 'bob', publishPrekeys: false);
      final alice = await Phone.create(db, 'alice');
      await alice.chat.startChat('bob');
      await expectLater(
        alice.chat.sendText(chatId, 'x'),
        throwsA(isA<ChatException>()),
      );
      expect(
        (await db.collection('chats/$chatId/messages').get()).docs,
        isEmpty,
      );
    });

    test(
      'one stale device without prekeys does not block delivery to the others',
      () async {
        final bob = await Phone.create(db, 'bob');
        // second device of bob that never ran the new code
        final dk = await DeviceKeys.generate();
        final b2 = await dk.certify(bob.device.identity, 'bob');
        await db.collection('users/bob/devices').doc(dk.deviceId).set({
          ...b2.toFirestore(),
          'createdAt': Timestamp.now(),
        });
        final alice = await Phone.create(db, 'alice');
        await alice.chat.startChat('bob');
        bob.sub = bob.chat.startSync(chatId);
        await alice.chat.sendText(chatId, 'still delivered');
        await eventually(
          () async => (await bob.bodies(chatId)).contains('still delivered'),
          'delivered',
        );
        await bob.sub?.cancel();
      },
    );

    test('v1-era stored sessions are discarded and replaced by a fresh handshake', () async {
      final bob = await Phone.create(db, 'bob');
      final alice = await Phone.create(db, 'alice');
      await alice.chat.startChat('bob');
      bob.sub = bob.chat.startSync(chatId);
      await alice.chat.sendText(chatId, 'one');
      await eventually(
        () async => (await bob.bodies(chatId)).contains('one'),
        'first',
      );
      // Downgrade the stored session records to the old version tag.
      final key =
          'sess:${alice.device.keys.deviceId}:bob:${bob.device.keys.deviceId}';
      final list = (jsonDecode((await alice.secrets.read(key))!) as List)
          .map((e) => {...Map<String, dynamic>.from(e), 'pv': 1})
          .toList();
      await alice.secrets.write(key, jsonEncode(list));
      await alice.chat.sendText(chatId, 'two');
      await eventually(
        () async => (await bob.bodies(chatId)).contains('two'),
        'after migration',
      );
      await bob.sub?.cancel();
    });
  });

  group('F-2: delivery survives a prekey that cannot be used', () {
    test('with one prekey left, only the first claimer gets it and the other falls back to the signed prekey', () async {
      final bob = await Phone.create(db, 'bob');
      final otps =
          (await bob.prekeyCol.where('kind', isEqualTo: 'onetime').get()).docs;
      for (final d in otps.skip(1)) {
        await bob.prekeys.consumeOneTime('bob', bob.device.keys.deviceId, d.id);
      }
      await addUser(db, 'carol');
      final alice = await Phone.create(db, 'alice');
      final carol = await Phone.create(db, 'carol');
      final target = (await alice.keys.fetchDevices('bob')).single;
      final first = await alice.prekeys.fetchBundle(target);
      final second = await carol.prekeys.fetchBundle(target);
      expect(first.oneTime, isNotNull);
      expect(second.oneTime, isNull);
      expect(
        (await bob.prekeyCol.where('kind', isEqualTo: 'onetime').get()).docs,
        isEmpty,
      );

      // both conversations work end to end (the second without a one-time prekey)
      await alice.chat.startChat('bob');
      await carol.chat.startChat('bob');
      bob.sub = bob.chat.startSync('alice_bob');
      final sub2 = bob.chat.startSync('bob_carol');
      await alice.chat.sendText('alice_bob', 'from alice');
      await carol.chat.sendText('bob_carol', 'from carol');
      await eventually(
        () async => (await bob.bodies('alice_bob')).contains('from alice'),
        'alice delivered',
      );
      await eventually(
        () async => (await bob.bodies('bob_carol')).contains('from carol'),
        'carol delivered',
      );
      await sub2.cancel();
      await bob.sub?.cancel();
    });

    test('orphaned published prekeys (private halves lost) are cleaned up and the pool refilled', () async {
      final bob = await Phone.create(db, 'bob');
      final key = 'prekeys:bob:${bob.device.keys.deviceId}';
      final stored =
          jsonDecode((await bob.secrets.read(key))!) as Map<String, dynamic>;
      stored['oneTime'] = <String, dynamic>{};
      await bob.secrets.write(key, jsonEncode(stored));
      final before =
          (await bob.prekeyCol.where('kind', isEqualTo: 'onetime').get()).docs
              .map((d) => d.id)
              .toSet();
      expect(before, hasLength(PreKeyService.poolTarget));
      await bob.prekeys.maintain('bob', bob.device);
      final after =
          (await bob.prekeyCol.where('kind', isEqualTo: 'onetime').get()).docs
              .map((d) => d.id)
              .toSet();
      expect(after, hasLength(PreKeyService.poolTarget));
      expect(
        after.intersection(before),
        isEmpty,
        reason: 'none of the orphans survive',
      );
      final local =
          jsonDecode((await bob.secrets.read(key))!) as Map<String, dynamic>;
      expect(
        (local['oneTime'] as Map).keys.toSet(),
        after,
        reason: 'every published prekey has a private half',
      );
    });

    test('a claimed prekey is gone from the server immediately, so it cannot be offered twice', () async {
      final bob = await Phone.create(db, 'bob');
      final alice = await Phone.create(db, 'alice');
      final target = (await alice.keys.fetchDevices('bob')).single;
      final before =
          (await bob.prekeyCol.where('kind', isEqualTo: 'onetime').get())
              .docs
              .length;
      final b = await alice.prekeys.fetchBundle(target);
      expect(b.oneTime, isNotNull);
      final after =
          (await bob.prekeyCol.where('kind', isEqualTo: 'onetime').get()).docs;
      expect(after.length, before - 1);
      expect(after.map((d) => d.id), isNot(contains(b.oneTime!.id)));
    });

    test('if the receiver lost the private prekey, the sender recovers with a fresh session after the stale period', () async {
      final bob = await Phone.create(db, 'bob');
      final alice = await Phone.create(db, 'alice');
      await alice.chat.startChat('bob');
      await bob.chat.acceptRequest('alice_bob');
      bob.sub = bob.chat.startSync('alice_bob');

      // Bob loses the private halves of every one-time prekey (data loss / restore).
      final key = 'prekeys:bob:${bob.device.keys.deviceId}';
      final stored =
          jsonDecode((await bob.secrets.read(key))!) as Map<String, dynamic>;
      stored['oneTime'] = <String, dynamic>{};
      await bob.secrets.write(key, jsonEncode(stored));

      await alice.chat.sendText('alice_bob', 'lost one');
      await eventually(
        () async =>
            (await bob.bodies('alice_bob'))
                .contains('Encryption key no longer available.'),
        'visible failure on the receiver',
      );
      // Further messages on the same session fail the same way: that is the problem F-2 describes.
      await alice.chat.sendText('alice_bob', 'lost two');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect((await bob.bodies('alice_bob')).contains('lost two'), isFalse);

      // Bob's app restarts: it notices the published prekeys it cannot answer, removes
      // them and publishes fresh ones. (A failing handshake also triggers this by itself.)
      await bob.prekeys.maintain('bob', bob.device);

      // Time passes (the session was never answered): age the sender's stored session.
      final sk =
          'sess:${alice.device.keys.deviceId}:bob:${bob.device.keys.deviceId}';
      final list = (jsonDecode((await alice.secrets.read(sk))!) as List)
          .map(
            (e) => {
              ...Map<String, dynamic>.from(e),
              'createdAt': DateTime.now()
                  .subtract(const Duration(days: 2))
                  .millisecondsSinceEpoch,
            },
          )
          .toList();
      await alice.secrets.write(sk, jsonEncode(list));

      await alice.chat.sendText('alice_bob', 'recovered');
      await eventually(
        () async => (await bob.bodies('alice_bob')).contains('recovered'),
        'a fresh session delivers',
      );
      // the stale session is kept (late replies on it must still work), the new one is used from now on
      final sessions = jsonDecode((await alice.secrets.read(sk))!) as List;
      expect(sessions.length, 2);
      await alice.chat.sendText('alice_bob', 'and again');
      await eventually(
        () async => (await bob.bodies('alice_bob')).contains('and again'),
        'continues',
      );
      await bob.sub?.cancel();
    });

    test('a session that was answered is never replaced, however old', () async {
      final bob = await Phone.create(db, 'bob');
      final alice = await Phone.create(db, 'alice');
      await alice.chat.startChat('bob');
      await bob.chat.acceptRequest('alice_bob');
      bob.sub = bob.chat.startSync('alice_bob');
      alice.sub = alice.chat.startSync('alice_bob');
      await alice.chat.sendText('alice_bob', 'hello');
      await eventually(
        () async => (await bob.bodies('alice_bob')).contains('hello'),
        'delivered',
      );
      await bob.chat.sendText('alice_bob', 'hi back');
      await eventually(
        () async => (await alice.bodies('alice_bob')).contains('hi back'),
        'answered',
      );
      final sk =
          'sess:${alice.device.keys.deviceId}:bob:${bob.device.keys.deviceId}';
      final aged = (jsonDecode((await alice.secrets.read(sk))!) as List)
          .map(
            (e) => {
              ...Map<String, dynamic>.from(e),
              'createdAt': DateTime.now()
                  .subtract(const Duration(days: 60))
                  .millisecondsSinceEpoch,
            },
          )
          .toList();
      await alice.secrets.write(sk, jsonEncode(aged));
      await alice.chat.sendText('alice_bob', 'still the same session');
      await eventually(
        () async =>
            (await bob.bodies('alice_bob')).contains('still the same session'),
        'delivered',
      );
      expect((jsonDecode((await alice.secrets.read(sk))!) as List).length, 1);
      await alice.sub?.cancel();
      await bob.sub?.cancel();
    });
  });

  group('session choice', () {
    test(
      'prefers an answered session; otherwise the newest unanswered one',
      () async {
        final a = await Party.create('alice');
        final b = await Party.create('bob');
        Future<Session> mk() async => (await Session.initiate(
          local: a.keys,
          localBundle: a.bundle,
          remote: await b.pk.claim(),
        )).$1;
        final old = await mk();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final newer = await mk();
        expect(
          ChatService.pickSession([old, newer])!.sessionId,
          newer.sessionId,
        );
        expect(ChatService.pickSession([]), isNull);
      },
    );
  });
}

// tiny placeholders for syntactically valid handshake bytes in lookups
List<int> _z(int n) => List<int>.filled(n, 0);
// ignore: non_constant_identifier_names
Uint8List Uint8List32() => Uint8List.fromList(_z(32));
// ignore: non_constant_identifier_names
Uint8List Uint8List1088() => Uint8List.fromList(_z(1088));

class Party {
  Party(this.uid, this.identity, this.keys, this.bundle, this.pk);
  final String uid;
  final AccountIdentity identity;
  final DeviceKeys keys;
  final DeviceBundle bundle;
  final PreKeyed pk;
  static Future<Party> create(String uid) async {
    final id = await AccountIdentity.generate();
    final keys = await DeviceKeys.generate();
    final bundle = await keys.certify(id, uid);
    return Party(uid, id, keys, bundle, await preKeyed(bundle, id));
  }
}

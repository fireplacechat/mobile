import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> eventually(Future<bool> Function() cond, String why) async {
  for (var i = 0; i < 120; i++) {
    if (await cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  fail('timed out: $why');
}

class Phone {
  Phone(this.db, this.uid);
  final FakeFirebaseFirestore db;
  final String uid;
  final secrets = MemorySecretStore();
  final messages = MemoryMessageStore();
  late final KeyService keys;
  late final LocalDevice device;
  late final PreKeyService prekeys;
  late final ChatService chat;
  StreamSubscription<void>? sub;

  static Future<Phone> create(FakeFirebaseFirestore db, String uid) async {
    final p = Phone(db, uid);
    p.keys = KeyService(db, p.secrets);
    p.device = await p.keys.ensureDevice(uid);
    p.prekeys = PreKeyService(db, p.secrets);
    await p.prekeys.maintain(uid, p.device);
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

  Future<List<String>> bodies(String chatId) async =>
      (await messages.watch(chatId).first).map((m) => m.body).toList();
}

Map<String, dynamic> j(String raw) => jsonDecode(raw) as Map<String, dynamic>;

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  group('M-5: corrupted local keys are never used, never replaced by a new identity', () {
    Future<(Phone, String)> alice() async {
      final p = await Phone.create(db, 'alice');
      return (p, p.device.keys.deviceId);
    }

    test('device keys whose public half no longer matches -> recovery required, nothing minted', () async {
      final (a, devId) = await alice();
      final other = await DeviceKeys.generate();
      final bad = j((await a.secrets.read('device:alice'))!)
        ..['kemPub'] = b64(other.kemPub);
      await a.secrets.write('device:alice', jsonEncode(bad));
      final before = (await db.collection('users/alice/devices').get()).docs
          .map((d) => d.id)
          .toList();
      await expectLater(
        KeyService(db, a.secrets).ensureDevice('alice'),
        throwsA(isA<NeedsRecoveryException>()),
      );
      expect(
        (await db.collection('users/alice/devices').get()).docs
            .map((d) => d.id)
            .toList(),
        before,
      );
      expect(before, [devId]);
    });

    test('an identity whose halves are mixed up is refused too', () async {
      final (a, _) = await alice();
      final stranger = await AccountIdentity.generate();
      final bad = j((await a.secrets.read('identity:alice'))!)
        ..['dsaPub'] = b64(stranger.dsaPub);
      await a.secrets.write('identity:alice', jsonEncode(bad));
      await expectLater(
        KeyService(db, a.secrets).ensureDevice('alice'),
        throwsA(isA<NeedsRecoveryException>()),
      );
    });

    test(
      'a stored bundle that no longer matches the keys is refused',
      () async {
        final (a, _) = await alice();
        final other = await DeviceKeys.generate();
        final bad = j((await a.secrets.read('bundle:alice'))!)
          ..['x25519Pub'] = b64(other.x25519Pub);
        await a.secrets.write('bundle:alice', jsonEncode(bad));
        await expectLater(
          KeyService(db, a.secrets).ensureDevice('alice'),
          throwsA(isA<NeedsRecoveryException>()),
        );
      },
    );

    test(
      'truncated or garbage records are refused instead of crashing',
      () async {
        final (a, _) = await alice();
        await a.secrets.write('device:alice', '{"deviceId": 5}');
        await expectLater(
          KeyService(db, a.secrets).ensureDevice('alice'),
          throwsA(isA<NeedsRecoveryException>()),
        );
        await a.secrets.write('device:alice', 'not json at all');
        await expectLater(
          KeyService(db, a.secrets).ensureDevice('alice'),
          throwsA(isA<NeedsRecoveryException>()),
        );
      },
    );

    test('healthy records still load', () async {
      final (a, devId) = await alice();
      final again = await KeyService(db, a.secrets).ensureDevice('alice');
      expect(again.keys.deviceId, devId);
    });
  });

  group('damaged stored state is repaired automatically', () {
    for (final id in ['alice', 'bob']) {
      setUp(() async {
        await db.collection('usernames').doc(id).set({'uid': id});
        await db.collection('users').doc(id).set({'username': id});
      });
    }

    test('a stored session whose ratchet key pair is inconsistent is dropped and a fresh handshake delivers', () async {
      final alice = await Phone.create(db, 'alice');
      final bob = await Phone.create(db, 'bob');
      await alice.chat.startChat('bob');
      await bob.chat.acceptRequest('alice_bob');
      await alice.chat.sendText('alice_bob', 'first');
      final key =
          'sess:${alice.device.keys.deviceId}:bob:${bob.device.keys.deviceId}';
      final list = (jsonDecode((await alice.secrets.read(key))!) as List)
          .cast<Map<String, dynamic>>();
      final other = await PreKeyRecord.generate();
      (list.first['st'] as Map)['dhsPub'] = b64(
        other.x25519Pub,
      ); // right size, wrong key
      await alice.secrets.write(key, jsonEncode(list));
      await alice.chat.sendText('alice_bob', 'after corruption');
      bob.sub = bob.chat.startSync('alice_bob');
      await eventually(
        () async =>
            (await bob.bodies('alice_bob')).contains('after corruption'),
        'delivered',
      );
      await bob.sub?.cancel();
    });

    test('a damaged one-time prekey record is dropped and its published copy removed (the pool refills once it runs low)', () async {
      final bob = await Phone.create(db, 'bob');
      final key = 'prekeys:bob:${bob.device.keys.deviceId}';
      final stored = j((await bob.secrets.read(key))!);
      final oneTime = stored['oneTime'] as Map<String, dynamic>;
      final victim = oneTime.keys.first;
      final other = await PreKeyRecord.generate();
      (oneTime[victim] as Map<String, dynamic>)['x25519Pub'] = b64(
        other.x25519Pub,
      );
      await bob.secrets.write(key, jsonEncode(stored));
      await bob.prekeys.maintain('bob', bob.device);
      final published =
          (await db
                  .collection(
                    'users/bob/devices/${bob.device.keys.deviceId}/prekeys',
                  )
                  .where('kind', isEqualTo: 'onetime')
                  .get())
              .docs
              .map((d) => d.id)
              .toSet();
      expect(published, isNot(contains(victim)));
      expect(published.length, PreKeyService.poolTarget - 1);
      final local = (j((await bob.secrets.read(key))!)['oneTime'] as Map).keys
          .toSet();
      expect(published.difference(local), isEmpty);
    });

    test(
      'an unreadable prekey store is replaced instead of crashing',
      () async {
        final bob = await Phone.create(db, 'bob');
        await bob.secrets.write(
          'prekeys:bob:${bob.device.keys.deviceId}',
          '{{{{ not json',
        );
        await bob.prekeys.maintain('bob', bob.device); // must not throw
        final published =
            (await db
                    .collection(
                      'users/bob/devices/${bob.device.keys.deviceId}/prekeys',
                    )
                    .where('kind', isEqualTo: 'signed')
                    .get())
                .docs;
        expect(published, isNotEmpty);
      },
    );
  });

  group('M-10: link requests expire', () {
    test('a link request older than 15 minutes is refused, a fresh one is accepted', () async {
      final secrets = MemorySecretStore();
      final keys = KeyService(db, secrets);
      final dev = await keys.ensureDevice('alice');
      final existing = RecoveryService(db, secrets, keys);
      final newSecrets = MemorySecretStore();
      final fresh = RecoveryService(db, newSecrets, KeyService(db, newSecrets));
      final req = await fresh.startLink('alice');
      // age the request
      await db
          .collection('users/alice/linkRequests')
          .doc(req.keys.deviceId)
          .update({
            'createdAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(minutes: 20)),
            ),
          });
      await expectLater(
        existing.approveLink('alice', dev.identity, req.qrPayload),
        throwsA(
          isA<RecoveryException>().having(
            (e) => e.message,
            'message',
            contains('expired'),
          ),
        ),
      );
      final req2 = await fresh.startLink('alice');
      final code = await existing.approveLink(
        'alice',
        dev.identity,
        req2.qrPayload,
      );
      expect(code, matches(RegExp(r'^\d{6}$')));
    });
  });
}

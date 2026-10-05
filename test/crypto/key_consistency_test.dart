import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fireplace/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> j(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

void main() {
  test('KeyChecks: X25519 and ML-KEM public/private correspondence', () async {
    final a = await DeviceKeys.generate();
    final b = await DeviceKeys.generate();
    expect(await KeyChecks.x25519Matches(a.x25519Seed, a.x25519Pub), isTrue);
    expect(await KeyChecks.x25519Matches(a.x25519Seed, b.x25519Pub), isFalse);
    expect(KeyChecks.mlKem768Matches(a.kemSecret, a.kemPub), isTrue);
    expect(KeyChecks.mlKem768Matches(a.kemSecret, b.kemPub), isFalse);
    expect(KeyChecks.mlKem768Matches(Uint8List(5), a.kemPub), isFalse);
    expect(await KeyChecks.x25519Matches([1, 2], a.x25519Pub), isFalse);
  });

  group('DeviceKeys', () {
    test('a fresh key set is consistent and round-trips', () async {
      final k = await DeviceKeys.generate();
      expect(await k.consistent(), isTrue);
      expect(await DeviceKeys.fromJson(k.toJson()).consistent(), isTrue);
    });

    test('mismatched public keys load but are reported inconsistent; bad shapes are refused', () async {
      final a = await DeviceKeys.generate();
      final b = await DeviceKeys.generate();
      final swappedX = j(a.toJson())..['x25519Pub'] = b64(b.x25519Pub);
      final swappedKem = j(a.toJson())..['kemPub'] = b64(b.kemPub);
      expect(await DeviceKeys.fromJson(swappedX).consistent(), isFalse);
      expect(await DeviceKeys.fromJson(swappedKem).consistent(), isFalse);
      for (final bad in [
        j(a.toJson())..['deviceId'] = 'x',
        j(a.toJson())..['x25519Seed'] = b64([1, 2, 3]),
        j(a.toJson())..['kemSecret'] = 5,
        j(a.toJson())..remove('kemPub'),
      ]) {
        expect(() => DeviceKeys.fromJson(bad), throwsA(anything));
      }
    });
  });

  group('AccountIdentity', () {
    test('consistent when whole, inconsistent when halves are mixed', () async {
      final a = await AccountIdentity.generate();
      final b = await AccountIdentity.generate();
      expect(await a.consistent(), isTrue);
      expect(await AccountIdentity.fromJson(a.toJson()).consistent(), isTrue);
      final mixedEd = j(a.toJson())..['edPub'] = b64(b.edPub);
      final mixedDsa = j(a.toJson())..['dsaPub'] = b64(b.dsaPub);
      expect(await AccountIdentity.fromJson(mixedEd).consistent(), isFalse);
      expect(await AccountIdentity.fromJson(mixedDsa).consistent(), isFalse);
    });

    test('wrong lengths and types are refused', () async {
      final a = await AccountIdentity.generate();
      for (final bad in [
        j(a.toJson())..['edSeed'] = b64([1]),
        j(a.toJson())..['dsaSecret'] = b64(Uint8List(10)),
        j(a.toJson())..['dsaPub'] = 3,
        j(a.toJson())..remove('edPub'),
      ]) {
        expect(() => AccountIdentity.fromJson(bad), throwsA(anything));
      }
    });
  });

  group('PreKeyRecord', () {
    test(
      'fresh records are consistent; mismatches and bad shapes are caught',
      () async {
        final r = await PreKeyRecord.generate();
        final other = await PreKeyRecord.generate();
        expect(await r.consistent(), isTrue);
        expect(await PreKeyRecord.fromJson(r.toJson()).consistent(), isTrue);
        final bad = PreKeyRecord.fromJson(
          j(r.toJson())..['x25519Pub'] = b64(other.x25519Pub),
        );
        expect(await bad.consistent(), isFalse);
        final bad2 = PreKeyRecord.fromJson(
          j(r.toJson())..['kemPub'] = b64(other.kemPub),
        );
        expect(await bad2.consistent(), isFalse);
        for (final m in [
          j(r.toJson())..['id'] = '',
          j(r.toJson())..['createdAt'] = 'yesterday',
          j(r.toJson())..['kemSecret'] = b64(Uint8List(3)),
          j(r.toJson())..remove('x25519Seed'),
        ]) {
          expect(() => PreKeyRecord.fromJson(m), throwsA(anything));
        }
      },
    );
  });

  test(
    'Session.selfCheck notices a ratchet key pair that no longer matches',
    () async {
      final a = await AccountIdentity.generate();
      final ak = await DeviceKeys.generate();
      final ab = await ak.certify(a, 'alice');
      final b = await AccountIdentity.generate();
      final bk = await DeviceKeys.generate();
      final bb = await bk.certify(b, 'bob');
      final spk = await PreKeyRecord.generate();
      final signed = await PreKeys.sign(spk, b, 'bob', bb.deviceId);
      final (s, _) = await Session.initiate(
        local: ak,
        localBundle: ab,
        remote: PreKeyBundle(device: bb, signed: signed),
      );
      expect(await s.selfCheck(), isTrue);
      final json = j(s.toJson());
      final other = await PreKeyRecord.generate();
      (json['st'] as Map)['dhsPub'] = b64(
        other.x25519Pub,
      ); // valid length, wrong key
      final loaded = Session.tryFromJson(json)!; // structure is fine...
      expect(await loaded.selfCheck(), isFalse); // ...but the key pair is not
      final json2 = j(s.toJson());
      (json2['st'] as Map)['kemPub'] = b64(other.kemPub);
      expect(await Session.tryFromJson(json2)!.selfCheck(), isFalse);
    },
  );

  test('protocol labels are pinned: changing any one changes every derived key, so it must be deliberate', () {
    expect(protocolLabels, const {
      'handshake transcript': 'fireplace/v2/handshake',
      'root key': 'fireplace/v3/root',
      'ratchet step': 'fireplace/v3/ratchet',
      'message key': 'fireplace/v3/msg',
      'session id': 'fireplace/v4/sid',
      'message AAD': 'fireplace/v4/aad',
    });
    expect(protocolVersion, 4);
    expect(
      protocolLabels.values.toSet().length,
      protocolLabels.length,
      reason: 'labels must be distinct',
    );
  });

  test(
    'cheap malformed new-chain messages never count against the failure budget',
    () async {
      final alice = await AccountIdentity.generate();
      final ak = await DeviceKeys.generate();
      final ab = await ak.certify(alice, 'alice');
      final bob = await AccountIdentity.generate();
      final bk = await DeviceKeys.generate();
      final bb = await bk.certify(bob, 'bob');
      final spk = await PreKeyRecord.generate();
      final signed = await PreKeys.sign(spk, bob, 'bob', bb.deviceId);
      final (sa, hs) = await Session.initiate(
        local: ak,
        localBundle: ab,
        remote: PreKeyBundle(device: bb, signed: signed),
      );
      final sb = await Session.accept(
        local: bk,
        localBundle: bb,
        remote: ab,
        handshake: hs,
        signedPreKey: spk,
      );
      await sb.decrypt(
        await sa.encrypt(utf8.encode('hi'), chatId: 'c'),
        chatId: 'c',
      );
      final rnd = Random(5);
      Uint8List rand(int n) =>
          Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
      // 20 envelopes that are rejected on structure alone (huge counter) cost nothing
      for (var i = 0; i < 20; i++) {
        await expectLater(
          sb.decrypt(
            Envelope(
              n: Session.maxSkip + 10,
              pn: 0,
              sid: sb.sessionId,
              rx: rand(32),
              rk: rand(1184),
              rc: rand(1088),
              nonce: rand(12),
              ct: rand(8),
              mac: rand(16),
            ),
            chatId: 'c',
          ),
          throwsA(
            allOf(isA<SessionException>(), isNot(isA<SessionRateLimited>())),
          ),
        );
      }
      // so a genuine new chain (Bob replies, Alice answers on a new chain) still works
      await sa.decrypt(
        await sb.encrypt(utf8.encode('back'), chatId: 'c'),
        chatId: 'c',
      );
      final fresh = await sa.encrypt(utf8.encode('new chain'), chatId: 'c');
      expect(utf8.decode(await sb.decrypt(fresh, chatId: 'c')), 'new chain');
    },
  );
}

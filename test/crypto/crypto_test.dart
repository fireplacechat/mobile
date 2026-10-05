import 'dart:convert';
import 'dart:typed_data';

import 'package:fireplace/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/prekey_helpers.dart';

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

/// Starts a session from [a] to [b], consuming (a fresh claim of) b's prekeys.
Future<(Session, HandshakeInit)> initiate(
  Party a,
  Party b, {
  bool withOneTime = true,
}) async => Session.initiate(
  local: a.keys,
  localBundle: a.bundle,
  remote: await b.pk.claim(withOneTime: withOneTime),
);

Future<(Session, Session)> pair(
  Party a,
  Party b, {
  bool withOneTime = true,
}) async {
  final (sa, hs) = await initiate(a, b, withOneTime: withOneTime);
  final sb = await Session.accept(
    local: b.keys,
    localBundle: b.bundle,
    remote: a.bundle,
    handshake: hs,
    signedPreKey: b.pk.spk,
    oneTimePreKey: withOneTime ? b.pk.opk : null,
  );
  return (sa, sb);
}

Uint8List t(String s) => Uint8List.fromList(utf8.encode(s));
String s(List<int> b) => utf8.decode(b);

void main() {
  late Party alice, bob;
  setUpAll(() async {
    alice = await Party.create('alice');
    bob = await Party.create('bob');
  });

  group('identity & device certs', () {
    test('hybrid signature verifies; tampering fails', () async {
      final sig = await alice.identity.sign(t('hello'));
      expect(
        await AccountIdentity.verify(
          alice.identity.publicBytes,
          t('hello'),
          sig,
        ),
        isTrue,
      );
      expect(
        await AccountIdentity.verify(
          alice.identity.publicBytes,
          t('hellp'),
          sig,
        ),
        isFalse,
      );
      expect(
        await AccountIdentity.verify(bob.identity.publicBytes, t('hello'), sig),
        isFalse,
      );
      final bad = Uint8List.fromList(sig)..[10] ^= 1;
      expect(
        await AccountIdentity.verify(
          alice.identity.publicBytes,
          t('hello'),
          bad,
        ),
        isFalse,
      );
      expect(
        await AccountIdentity.verify(alice.identity.publicBytes, t('hello'), [
          1,
          2,
          3,
        ]),
        isFalse,
      );
    });

    test('a signature with only one valid half is rejected', () async {
      // Ed25519 half replaced by Bob's valid signature over the same message.
      final a = unlp0(await alice.identity.sign(t('m')));
      final b = unlp0(await bob.identity.sign(t('m')));
      final mixed = lpOf([b[0], a[1]]);
      expect(
        await AccountIdentity.verify(alice.identity.publicBytes, t('m'), mixed),
        isFalse,
      );
    });

    test('device cert verifies, binds uid/device/keys', () async {
      expect(await alice.bundle.verifyCert(), isTrue);
      final other = DeviceBundle(
        uid: 'mallory',
        deviceId: alice.bundle.deviceId,
        x25519Pub: alice.bundle.x25519Pub,
        kemPub: alice.bundle.kemPub,
        identityPub: alice.bundle.identityPub,
        cert: alice.bundle.cert,
      );
      expect(await other.verifyCert(), isFalse);
      final swapped = DeviceBundle(
        uid: 'alice',
        deviceId: alice.bundle.deviceId,
        x25519Pub: bob.bundle.x25519Pub,
        kemPub: alice.bundle.kemPub,
        identityPub: alice.bundle.identityPub,
        cert: alice.bundle.cert,
      );
      expect(await swapped.verifyCert(), isFalse);
    });

    test('firestore field sizes fit the deployed rules', () async {
      final m = alice.bundle.toFirestore();
      expect(m['x25519Pub']!.length <= 64, isTrue);
      expect(m['kemPub']!.length <= 2048, isTrue);
      expect(m['sigPub']!.length <= 4096, isTrue);
      expect(m['deviceCert']!.length <= 8192, isTrue);
      expect(
        RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(alice.bundle.deviceId),
        isTrue,
      );
    });

    test('serialization round trips', () async {
      final id2 = AccountIdentity.fromJson(alice.identity.toJson());
      final sig = await id2.sign(t('x'));
      expect(
        await AccountIdentity.verify(alice.identity.publicBytes, t('x'), sig),
        isTrue,
      );
      final k2 = DeviceKeys.fromJson(alice.keys.toJson());
      expect(k2.deviceId, alice.keys.deviceId);
      final b2 = DeviceBundle.fromFirestore(
        'alice',
        k2.deviceId,
        alice.bundle.toFirestore(),
      );
      expect(await b2.verifyCert(), isTrue);
    });
  });

  group('session', () {
    test('both directions round trip', () async {
      final (sa, sb) = await pair(alice, bob);
      final e1 = await sa.encrypt(t('hi bob'), chatId: 'c');
      expect(e1.handshake, isNotNull);
      expect(s(await sb.decrypt(e1, chatId: 'c')), 'hi bob');
      final e2 = await sb.encrypt(t('hi alice'), chatId: 'c');
      expect(e2.handshake, isNull);
      expect(s(await sa.decrypt(e2, chatId: 'c')), 'hi alice');
      expect(sa.acknowledged, isTrue);
      final e3 = await sa.encrypt(t('again'), chatId: 'c');
      expect(e3.handshake, isNull);
      expect(s(await sb.decrypt(e3, chatId: 'c')), 'again');
    });

    test('works without a one-time prekey (pool exhausted)', () async {
      final (sa, sb) = await pair(alice, bob, withOneTime: false);
      final e = await sa.encrypt(t('no opk'), chatId: 'c');
      expect(e.handshake!.opkId, isNull);
      expect(s(await sb.decrypt(e, chatId: 'c')), 'no opk');
    });

    test(
      'ciphertext does not contain plaintext; fresh nonce each message',
      () async {
        final (sa, _) = await pair(alice, bob);
        final e1 = await sa.encrypt(t('secret secret secret'), chatId: 'c');
        final e2 = await sa.encrypt(t('secret secret secret'), chatId: 'c');
        expect(
          utf8.decode(e1.ct, allowMalformed: true).contains('secret'),
          isFalse,
        );
        expect(e1.ct, isNot(e2.ct));
        expect(e1.nonce, isNot(e2.nonce));
      },
    );

    test('tampering with ct / mac / counter / chatId fails and does not corrupt state', () async {
      final (sa, sb) = await pair(alice, bob);
      final e = await sa.encrypt(t('payload'), chatId: 'c');
      Envelope with_({Uint8List? ct, Uint8List? mac, int? n}) => Envelope(
        n: n ?? e.n,
        pn: e.pn,
        sid: e.sid,
        rx: e.rx,
        rk: e.rk,
        rc: e.rc,
        nonce: e.nonce,
        ct: ct ?? e.ct,
        mac: mac ?? e.mac,
        handshake: e.handshake,
      );
      await expectLater(
        sb.decrypt(with_(ct: Uint8List.fromList(e.ct)..[0] ^= 1), chatId: 'c'),
        throwsA(isA<SessionException>()),
      );
      await expectLater(
        sb.decrypt(
          with_(mac: Uint8List.fromList(e.mac)..[0] ^= 1),
          chatId: 'c',
        ),
        throwsA(isA<SessionException>()),
      );
      await expectLater(
        sb.decrypt(with_(n: 1), chatId: 'c'),
        throwsA(isA<SessionException>()),
      );
      await expectLater(
        sb.decrypt(e, chatId: 'other-chat'),
        throwsA(isA<SessionException>()),
      );
      expect(s(await sb.decrypt(e, chatId: 'c')), 'payload');
    });

    test('replay is rejected', () async {
      final (sa, sb) = await pair(alice, bob);
      final e = await sa.encrypt(t('once'), chatId: 'c');
      await sb.decrypt(e, chatId: 'c');
      await expectLater(
        sb.decrypt(e, chatId: 'c'),
        throwsA(isA<SessionException>()),
      );
    });

    test(
      'out-of-order delivery works; each message decrypts exactly once',
      () async {
        final (sa, sb) = await pair(alice, bob);
        final es = [
          for (var i = 0; i < 5; i++) await sa.encrypt(t('m$i'), chatId: 'c'),
        ];
        for (final i in [3, 0, 4, 1, 2]) {
          expect(s(await sb.decrypt(es[i], chatId: 'c')), 'm$i');
        }
        await expectLater(
          sb.decrypt(es[2], chatId: 'c'),
          throwsA(isA<SessionException>()),
        );
      },
    );

    test('excessive gap is rejected', () async {
      final (sa, sb) = await pair(alice, bob);
      final e = await sa.encrypt(t('x'), chatId: 'c');
      final far = Envelope(
        n: Session.maxSkip + 5,
        pn: e.pn,
        sid: e.sid,
        rx: e.rx,
        rk: e.rk,
        rc: e.rc,
        nonce: e.nonce,
        ct: e.ct,
        mac: e.mac,
      );
      await expectLater(
        sb.decrypt(far, chatId: 'c'),
        throwsA(isA<SessionException>()),
      );
    });

    test(
      'a third party holding other prekeys cannot read the session',
      () async {
        final (sa, hs) = await initiate(alice, bob);
        final eve = await Party.create('eve');
        // Eve is handed Bob's handshake but has her own prekeys: accept refuses (id mismatch)...
        await expectLater(
          Session.accept(
            local: eve.keys,
            localBundle: eve.bundle,
            remote: alice.bundle,
            handshake: hs,
            signedPreKey: eve.pk.spk,
            oneTimePreKey: eve.pk.opk,
          ),
          throwsA(isA<SessionException>()),
        );
        // ...and even forcing her prekeys under Bob's ids gives keys that cannot decrypt.
        final forgedSpk = PreKeyRecord(
          id: hs.spkId,
          x25519Seed: eve.pk.spk.x25519Seed,
          x25519Pub: eve.pk.spk.x25519Pub,
          kemSecret: eve.pk.spk.kemSecret,
          kemPub: eve.pk.spk.kemPub,
          createdAt: DateTime.now(),
        );
        final forgedOpk = PreKeyRecord(
          id: hs.opkId!,
          x25519Seed: eve.pk.opk!.x25519Seed,
          x25519Pub: eve.pk.opk!.x25519Pub,
          kemSecret: eve.pk.opk!.kemSecret,
          kemPub: eve.pk.opk!.kemPub,
          createdAt: DateTime.now(),
        );
        final seve = await Session.accept(
          local: eve.keys,
          localBundle: eve.bundle,
          remote: alice.bundle,
          handshake: hs,
          signedPreKey: forgedSpk,
          oneTimePreKey: forgedOpk,
        );
        final e = await sa.encrypt(t('for bob'), chatId: 'c');
        await expectLater(
          seve.decrypt(e, chatId: 'c'),
          throwsA(isA<SessionException>()),
        );
      },
    );

    test('forward secrecy: with the prekey privates deleted, stolen long-term keys cannot rebuild the session', () async {
      final (sa, hs) = await initiate(alice, bob);
      final e = await sa.encrypt(t('old secret'), chatId: 'c');
      // Attacker later steals Bob's device keys (IK + KEM) and recorded hs + ciphertext,
      // but Bob already deleted the signed/one-time prekey privates. Best effort: use
      // different prekey privates under the recorded ids.
      final stolen = bob.keys;
      final guessSpk = await PreKeyRecord.generate();
      final guessOpk = await PreKeyRecord.generate();
      PreKeyRecord rename(PreKeyRecord r, String id) => PreKeyRecord(
        id: id,
        x25519Seed: r.x25519Seed,
        x25519Pub: r.x25519Pub,
        kemSecret: r.kemSecret,
        kemPub: r.kemPub,
        createdAt: r.createdAt,
      );
      final attacker = await Session.accept(
        local: stolen,
        localBundle: bob.bundle,
        remote: alice.bundle,
        handshake: hs,
        signedPreKey: rename(guessSpk, hs.spkId),
        oneTimePreKey: rename(guessOpk, hs.opkId!),
      );
      await expectLater(
        attacker.decrypt(e, chatId: 'c'),
        throwsA(isA<SessionException>()),
      );
    });

    test('transcript binds the prekey ids: altering them yields an unreadable session', () async {
      final (sa, hs) = await initiate(alice, bob);
      final e = await sa.encrypt(t('x'), chatId: 'c');
      // Same keys, but the handshake claims a different (attacker-chosen) prekey id.
      final spk = PreKeyRecord(
        id: 'attacker-id-1',
        x25519Seed: bob.pk.spk.x25519Seed,
        x25519Pub: bob.pk.spk.x25519Pub,
        kemSecret: bob.pk.spk.kemSecret,
        kemPub: bob.pk.spk.kemPub,
        createdAt: DateTime.now(),
      );
      final hs2 = HandshakeInit(
        ek: hs.ek,
        kemCt: hs.kemCt,
        spkId: 'attacker-id-1',
        opkId: hs.opkId,
        opkKemCt: hs.opkKemCt,
      );
      final sb = await Session.accept(
        local: bob.keys,
        localBundle: bob.bundle,
        remote: alice.bundle,
        handshake: hs2,
        signedPreKey: spk,
        oneTimePreKey: bob.pk.opk,
      );
      expect(sb.sessionId, isNot(sa.sessionId));
      await expectLater(
        sb.decrypt(e, chatId: 'c'),
        throwsA(isA<SessionException>()),
      );
    });

    test('forged/invalid certificate or prekey signature is refused', () async {
      final forged = DeviceBundle(
        uid: 'bob',
        deviceId: bob.bundle.deviceId,
        x25519Pub: bob.bundle.x25519Pub,
        kemPub: bob.bundle.kemPub,
        identityPub: alice.bundle.identityPub,
        cert: bob.bundle.cert,
      );
      final good = await bob.pk.claim();
      await expectLater(
        Session.initiate(
          local: alice.keys,
          localBundle: alice.bundle,
          remote: PreKeyBundle(
            device: forged,
            signed: good.signed,
            oneTime: good.oneTime,
          ),
        ),
        throwsA(isA<SessionException>()),
      );
      // prekey signed by someone else's identity
      final evilSigned = await PreKeys.sign(
        bob.pk.spk,
        alice.identity,
        'bob',
        bob.bundle.deviceId,
      );
      await expectLater(
        Session.initiate(
          local: alice.keys,
          localBundle: alice.bundle,
          remote: PreKeyBundle(
            device: bob.bundle,
            signed: evilSigned,
            oneTime: good.oneTime,
          ),
        ),
        throwsA(isA<SessionException>()),
      );
      // signature for a different device id cannot be replayed
      final other = await PreKeys.sign(
        bob.pk.spk,
        bob.identity,
        'bob',
        'some-other-device',
      );
      await expectLater(
        Session.initiate(
          local: alice.keys,
          localBundle: alice.bundle,
          remote: PreKeyBundle(device: bob.bundle, signed: other),
        ),
        throwsA(isA<SessionException>()),
      );
    });

    test('local keys that do not match the local bundle are refused', () async {
      final wrong = await DeviceKeys.generate();
      await expectLater(
        Session.initiate(
          local: wrong,
          localBundle: alice.bundle,
          remote: await bob.pk.claim(),
        ),
        throwsA(isA<SessionException>()),
      );
    });

    test(
      'tampered KEM ciphertext yields a session that cannot read messages',
      () async {
        final (sa, hs) = await initiate(alice, bob);
        final bad = HandshakeInit(
          ek: hs.ek,
          kemCt: Uint8List.fromList(hs.kemCt)..[5] ^= 1,
          spkId: hs.spkId,
          opkId: hs.opkId,
          opkKemCt: hs.opkKemCt,
        );
        final sb = await Session.accept(
          local: bob.keys,
          localBundle: bob.bundle,
          remote: alice.bundle,
          handshake: bad,
          signedPreKey: bob.pk.spk,
          oneTimePreKey: bob.pk.opk,
        );
        final e = await sa.encrypt(t('x'), chatId: 'c');
        await expectLater(
          sb.decrypt(e, chatId: 'c'),
          throwsA(isA<SessionException>()),
        );
      },
    );

    test('mismatched prekey ids are refused', () async {
      final (_, hs) = await initiate(alice, bob);
      await expectLater(
        Session.accept(
          local: bob.keys,
          localBundle: bob.bundle,
          remote: alice.bundle,
          handshake: hs,
          signedPreKey: bob.pk.spk,
          oneTimePreKey: null,
        ),
        throwsA(isA<SessionException>()),
      );
    });

    test('persistence: state survives toJson/fromJson mid-conversation; old versions are dropped', () async {
      final (sa, sb) = await pair(alice, bob);
      final e0 = await sa.encrypt(t('0'), chatId: 'c');
      final e1 = await sa.encrypt(t('1'), chatId: 'c');
      await sb.decrypt(e1, chatId: 'c');
      final sb2 = Session.fromJson(jsonDecode(jsonEncode(sb.toJson())));
      expect(s(await sb2.decrypt(e0, chatId: 'c')), '0');
      final sa2 = Session.fromJson(jsonDecode(jsonEncode(sa.toJson())));
      expect(
        s(
          await sb2.decrypt(
            await sa2.encrypt(t('2'), chatId: 'c'),
            chatId: 'c',
          ),
        ),
        '2',
      );
      final legacy = Map<String, dynamic>.from(sb.toJson())..['pv'] = 1;
      expect(Session.tryFromJson(legacy), isNull);
      final noVersion = Map<String, dynamic>.from(sb.toJson())..remove('pv');
      expect(Session.tryFromJson(noVersion), isNull);
    });
  });

  group('wire validation (before any crypto)', () {
    late Map<String, dynamic> good;
    setUp(() async {
      final (sa, _) = await pair(alice, bob);
      good = (await sa.encrypt(t('hello'), chatId: 'c')).toJson();
    });

    test('round trip and JSON encoding', () async {
      final e = Envelope.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(good))),
      );
      expect(e.n, 0);
      expect(e.handshake!.spkId, isNotEmpty);
    });

    Map<String, dynamic> mutate(void Function(Map<String, dynamic>) f) {
      final m = Map<String, dynamic>.from(jsonDecode(jsonEncode(good)));
      f(m);
      return m;
    }

    test('rejects wrong version, types, counters, lengths and inconsistent handshakes', () {
      final bad = <String, Map<String, dynamic>>{
        'old version': mutate((m) => m['pv'] = 1),
        'no version': mutate((m) => m.remove('pv')),
        'counter string': mutate((m) => m['n'] = 'x'),
        'negative counter': mutate((m) => m['n'] = -1),
        'huge counter': mutate((m) => m['n'] = 1099511627776),
        'sid number': mutate((m) => m['sid'] = 5),
        'sid long': mutate((m) => m['sid'] = 'x' * 100),
        'short nonce': mutate((m) => m['nonce'] = b64([1, 2, 3])),
        'nonce type': mutate((m) => m['nonce'] = 7),
        'short mac': mutate((m) => m['mac'] = b64([1, 2, 3])),
        'huge ct': mutate(
          (m) => m['ct'] = b64(Uint8List(Envelope.maxCiphertext + 1)),
        ),
        'bad base64': mutate((m) => m['ct'] = '***'),
        'hs not map': mutate((m) => m['hs'] = 'x'),
        'rx short': mutate((m) => m['rx'] = b64([1])),
        'rk short': mutate((m) => m['rk'] = b64([1])),
        'rc missing': mutate((m) => m.remove('rc')),
        'pn negative': mutate((m) => m['pn'] = -3),
        'hs short ek': mutate((m) => (m['hs'] as Map)['ek'] = b64([1])),
        'hs short kemCt': mutate((m) => (m['hs'] as Map)['kemCt'] = b64([1])),
        'hs no spk': mutate((m) => (m['hs'] as Map).remove('spk')),
        'hs opk without ct': mutate((m) => (m['hs'] as Map).remove('opkCt')),
        'hs ct without opk': mutate((m) => (m['hs'] as Map).remove('opk')),
        'hs long spk': mutate((m) => (m['hs'] as Map)['spk'] = 'x' * 99),
      };
      bad.forEach((name, json) {
        expect(
          () => Envelope.fromJson(json),
          throwsA(isA<FormatException>()),
          reason: name,
        );
      });
    });
  });

  group('prekey documents', () {
    test(
      'published prekeys round trip and sizes fit the deployed rules',
      () async {
        final spk = await PreKeys.sign(
          bob.pk.spk,
          bob.identity,
          'bob',
          bob.bundle.deviceId,
        );
        final doc = spk.toFirestore();
        expect((doc['x25519Pub'] as String).length <= 64, isTrue);
        expect((doc['kemPub'] as String).length <= 2048, isTrue);
        expect((doc['sig'] as String).length <= 8192, isTrue);
        final back = PublishedPreKey.fromFirestore(spk.id, doc);
        expect(await PreKeys.verifySigned(bob.bundle, back), isTrue);
        final opk = PreKeys.oneTime(bob.pk.opk!).toFirestore();
        expect(opk.containsKey('sig'), isFalse);
      },
    );

    test('malformed prekey documents are rejected', () async {
      final good = PreKeys.oneTime(bob.pk.opk!).toFirestore();
      for (final bad in <Map<String, dynamic>>[
        {...good, 'kind': 'weird'},
        {
          ...good,
          'x25519Pub': b64([1, 2]),
        },
        {...good, 'kemPub': 7},
        {...good, 'kind': 'signed'}, // signed requires a signature
      ]) {
        expect(
          () => PublishedPreKey.fromFirestore('id', bad),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });

  group('fingerprints', () {
    test(
      'safety number is symmetric, stable, 60 digits, and identity-specific',
      () async {
        final ab = await safetyNumber(
          alice.identity.publicBytes,
          bob.identity.publicBytes,
        );
        final ba = await safetyNumber(
          bob.identity.publicBytes,
          alice.identity.publicBytes,
        );
        expect(ab, ba);
        expect(ab.replaceAll(' ', '').length, 60);
        final eve = await Party.create('eve');
        expect(
          await safetyNumber(
            alice.identity.publicBytes,
            eve.identity.publicBytes,
          ),
          isNot(ab),
        );
        expect(
          await identityFingerprint(alice.identity.publicBytes),
          isNot(await identityFingerprint(bob.identity.publicBytes)),
        );
      },
    );
  });
}

// tiny local helpers (avoid exporting internals)
List<Uint8List> unlp0(List<int> d) {
  final v = ByteData.sublistView(Uint8List.fromList(d));
  final out = <Uint8List>[];
  var i = 0;
  while (i < d.length) {
    final l = v.getUint32(i);
    i += 4;
    out.add(Uint8List.fromList(d.sublist(i, i + l)));
    i += l;
  }
  return out;
}

Uint8List lpOf(List<List<int>> parts) {
  final b = BytesBuilder();
  for (final p in parts) {
    b.add((ByteData(4)..setUint32(0, p.length)).buffer.asUint8List());
    b.add(p);
  }
  return b.toBytes();
}

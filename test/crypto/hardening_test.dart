import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fireplace/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/prekey_helpers.dart';

Uint8List t(String s) => Uint8List.fromList(utf8.encode(s));

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

Future<(Session, HandshakeInit)> start(Party a, Party b) async =>
    Session.initiate(
      local: a.keys,
      localBundle: a.bundle,
      remote: await b.pk.claim(),
    );

Future<Session> acceptAs(
  Party responder,
  Party initiator,
  HandshakeInit hs, {
  DeviceBundle? initiatorBundle,
}) => Session.accept(
  local: responder.keys,
  localBundle: responder.bundle,
  remote: initiatorBundle ?? initiator.bundle,
  handshake: hs,
  signedPreKey: responder.pk.spk,
  oneTimePreKey: responder.pk.opk,
);

Session copy(Session s) => Session.fromJson(
  jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
);

Map<String, dynamic> json(Session s) =>
    jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;

void main() {
  late Party alice, bob, eve;
  setUpAll(() async {
    alice = await Party.create('alice');
    bob = await Party.create('bob');
    eve = await Party.create('eve');
  });

  group('F-1: the session id commits to the whole handshake', () {
    test(
      '128-bit url-safe id, identical on both sides, different per handshake',
      () async {
        final (sa, hs) = await start(alice, bob);
        final sb = await acceptAs(bob, alice, hs);
        expect(sa.sessionId, sb.sessionId);
        expect(sa.sessionId.length, 22);
        expect(RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(sa.sessionId), isTrue);
        final (sa2, _) = await start(alice, bob);
        expect(sa2.sessionId, isNot(sa.sessionId));
      },
    );

    test(
      'changing ANY handshake field changes the id or is rejected',
      () async {
        final (sa, hs) = await start(alice, bob);
        expect(hs.opkKemCt, isNotNull);
        Uint8List flip(Uint8List b) => Uint8List.fromList(b)..[7] ^= 1;
        final variants = <String, HandshakeInit>{
          'ek': HandshakeInit(
            ek: flip(hs.ek),
            kemCt: hs.kemCt,
            spkId: hs.spkId,
            opkId: hs.opkId,
            opkKemCt: hs.opkKemCt,
          ),
          'kemCt': HandshakeInit(
            ek: hs.ek,
            kemCt: flip(hs.kemCt),
            spkId: hs.spkId,
            opkId: hs.opkId,
            opkKemCt: hs.opkKemCt,
          ),
          'opkKemCt': HandshakeInit(
            ek: hs.ek,
            kemCt: hs.kemCt,
            spkId: hs.spkId,
            opkId: hs.opkId,
            opkKemCt: flip(hs.opkKemCt!),
          ),
          'spkId': HandshakeInit(
            ek: hs.ek,
            kemCt: hs.kemCt,
            spkId: '${hs.spkId}x',
            opkId: hs.opkId,
            opkKemCt: hs.opkKemCt,
          ),
          'opkId': HandshakeInit(
            ek: hs.ek,
            kemCt: hs.kemCt,
            spkId: hs.spkId,
            opkId: '${hs.opkId}x',
            opkKemCt: hs.opkKemCt,
          ),
        };
        for (final e in variants.entries) {
          try {
            final s = await acceptAs(bob, alice, e.value);
            expect(
              s.sessionId,
              isNot(sa.sessionId),
              reason: '${e.key} did not change the id',
            );
          } on SessionException {
            // rejected before a session exists: also fine
          }
        }
      },
    );

    test('the same handshake bytes attributed to a different initiator get a different id', () async {
      final (sa, hs) = await start(alice, bob);
      // Eve's (valid) certificate in place of Alice's: identities/devices are in the transcript.
      final other = await acceptAs(bob, eve, hs, initiatorBundle: eve.bundle);
      expect(other.sessionId, isNot(sa.sessionId));
    });

    test(
      'an envelope that names a different session id never authenticates',
      () async {
        final (sa, hs) = await start(alice, bob);
        final sb = await acceptAs(bob, alice, hs);
        final e = await sa.encrypt(t('x'), chatId: 'c');
        final forged = Envelope(
          n: e.n,
          pn: e.pn,
          sid: 'AAAAAAAAAAAAAAAAAAAAAA',
          rx: e.rx,
          rk: e.rk,
          rc: e.rc,
          nonce: e.nonce,
          ct: e.ct,
          mac: e.mac,
        );
        await expectLater(
          sb.decrypt(forged, chatId: 'c'),
          throwsA(isA<SessionException>()),
        );
        expect(utf8.decode(await sb.decrypt(e, chatId: 'c')), 'x');
      },
    );
  });

  group('F-4: stored session state is validated on load', () {
    late Map<String, dynamic> initiator, responder;
    setUp(() async {
      final (sa, hs) = await start(alice, bob);
      final sb = await acceptAs(bob, alice, hs);
      initiator = json(sa);
      await sb.decrypt(await sa.encrypt(t('1'), chatId: 'c'), chatId: 'c');
      await sa.decrypt(await sb.encrypt(t('2'), chatId: 'c'), chatId: 'c');
      final e0 = await sa.encrypt(t('3'), chatId: 'c');
      final e1 = await sa.encrypt(t('4'), chatId: 'c');
      await sb.decrypt(e1, chatId: 'c'); // leaves a skipped key
      expect(e0, isNotNull);
      responder = json(sb);
      initiator = json(sa);
    });

    test('valid state loads, both roles', () {
      expect(Session.tryFromJson(initiator), isNotNull);
      expect(Session.tryFromJson(responder), isNotNull);
      expect((responder['st'] as Map)['skipped'], isNotEmpty);
    });

    Map<String, dynamic> mutate(
      Map<String, dynamic> base,
      void Function(Map<String, dynamic>) f,
    ) {
      final m = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
      f(m);
      return m;
    }

    test(
      'wrong types, missing fields, bad lengths and ranges are all rejected',
      () {
        final bad = <String, void Function(Map<String, dynamic>)>{
          'no uid': (m) => m.remove('localUid'),
          'uid number': (m) => m['localUid'] = 5,
          'uid empty': (m) => m['localUid'] = '',
          'sid huge': (m) => m['sid'] = 'x' * 100,
          'role string': (m) => m['isInitiator'] = 'yes',
          'createdAt string': (m) => m['createdAt'] = 'now',
          'createdAt negative': (m) => m['createdAt'] = -1,
          'state missing': (m) => m.remove('st'),
          'state list': (m) => m['st'] = [],
          'rk short': (m) => (m['st'] as Map)['rk'] = b64([1, 2, 3]),
          'rk number': (m) => (m['st'] as Map)['rk'] = 7,
          'seed long': (m) => (m['st'] as Map)['dhsSeed'] = b64(Uint8List(64)),
          'kem secret short': (m) =>
              (m['st'] as Map)['kemSecret'] = b64(Uint8List(10)),
          'kem pub short': (m) =>
              (m['st'] as Map)['kemPub'] = b64(Uint8List(10)),
          'ns negative': (m) => (m['st'] as Map)['ns'] = -1,
          'nr string': (m) => (m['st'] as Map)['nr'] = '3',
          'pn huge': (m) => (m['st'] as Map)['pn'] = 1099511627776,
          'cks short': (m) => (m['st'] as Map)['cks'] = b64(Uint8List(5)),
          'cks without pendingCt': (m) => (m['st'] as Map).remove('pendingCt'),
          'pendingCt without cks': (m) {
            (m['st'] as Map).remove('cks');
          },
          'pendingCt short': (m) =>
              (m['st'] as Map)['pendingCt'] = b64(Uint8List(9)),
          'ckr without dhr': (m) => (m['st'] as Map).remove('dhrPub'),
          'skipped list': (m) => (m['st'] as Map)['skipped'] = [],
          'retired not a list': (m) => (m['st'] as Map)['retired'] = 'x',
          'retired bad key': (m) =>
              (m['st'] as Map)['retired'] = [b64(Uint8List(5))],
          'retired too many': (m) => (m['st'] as Map)['retired'] = [
            for (var i = 0; i < 65; i++) b64(Uint8List(32)),
          ],
          'skipped bad key': (m) =>
              (m['st'] as Map)['skipped'] = {'nope': b64(Uint8List(32))},
          'skipped short value': (m) => (m['st'] as Map)['skipped'] = {
            '${b64(Uint8List(32))}:1': b64(Uint8List(3)),
          },
          'skipped too many': (m) => (m['st'] as Map)['skipped'] = {
            for (var i = 0; i <= Session.maxSkip; i++)
              '${b64(Uint8List(32))}:$i': b64(Uint8List(32)),
          },
          'handshake garbage': (m) => m['hs'] = {'ek': 'x'},
          'handshake not map': (m) => m['hs'] = 'x',
        };
        for (final e in bad.entries) {
          final target =
              e.key == 'handshake garbage' || e.key == 'handshake not map'
              ? initiator
              : responder;
          expect(
            Session.tryFromJson(mutate(target, e.value)),
            isNull,
            reason: e.key,
          );
          expect(
            () => Session.fromJson(mutate(target, e.value)),
            throwsA(anything),
            reason: e.key,
          );
        }
      },
    );

    test('an initiator without a sending chain and a responder with a handshake are rejected', () {
      expect(
        Session.tryFromJson(
          mutate(initiator, (m) {
            (m['st'] as Map).remove('cks');
            (m['st'] as Map).remove('pendingCt');
          }),
        ),
        isNull,
      );
      expect(
        Session.tryFromJson(
          mutate(responder, (m) => m['hs'] = initiator['hs'] ?? {'ek': 'x'}),
        ),
        isNull,
      );
    });

    test('random corruption never throws out of tryFromJson', () {
      final rnd = Random(7);
      for (var i = 0; i < 400; i++) {
        final m = mutate(i.isEven ? initiator : responder, (m) {
          void corrupt(Map<String, dynamic> node) {
            final keys = node.keys.toList();
            if (keys.isEmpty) return;
            final k = keys[rnd.nextInt(keys.length)];
            final v = node[k];
            switch (rnd.nextInt(5)) {
              case 0:
                node.remove(k);
              case 1:
                node[k] = rnd.nextInt(1000);
              case 2:
                node[k] = null;
              case 3:
                if (v is String && v.isNotEmpty) {
                  node[k] = v.substring(0, rnd.nextInt(v.length));
                }
              default:
                if (v is Map) corrupt(Map<String, dynamic>.from(v));
            }
          }

          corrupt(m);
          final st = m['st'];
          if (st is Map<String, dynamic>) corrupt(st);
        });
        expect(() => Session.tryFromJson(m), returnsNormally);
      }
    });
  });

  group('F-5: invalid new-chain traffic stops costing work', () {
    test('after 8 failed attempts the session refuses new-chain work, ordinary traffic still flows', () async {
      final (sa, hs) = await start(alice, bob);
      final sb = await acceptAs(bob, alice, hs);
      await sb.decrypt(await sa.encrypt(t('hello'), chatId: 'c'), chatId: 'c');

      final rnd = Random(3);
      Uint8List rand(int n) =>
          Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
      Envelope forged() => Envelope(
        n: 0,
        pn: 0,
        sid: sb.sessionId,
        rx: rand(32),
        rk: rand(1184),
        rc: rand(1088),
        nonce: rand(12),
        ct: rand(40),
        mac: rand(16),
      );
      for (var i = 0; i < 8; i++) {
        await expectLater(
          sb.decrypt(forged(), chatId: 'c'),
          throwsA(
            allOf(isA<SessionException>(), isNot(isA<SessionRateLimited>())),
          ),
          reason: 'attempt $i',
        );
      }
      final sw = Stopwatch()..start();
      await expectLater(
        sb.decrypt(forged(), chatId: 'c'),
        throwsA(isA<SessionRateLimited>()),
      );
      expect(
        sw.elapsedMilliseconds,
        lessThan(100),
      ); // refused before any key work

      // messages on the existing chain are unaffected
      final ok = await sa.encrypt(t('still fine'), chatId: 'c');
      expect(utf8.decode(await sb.decrypt(ok, chatId: 'c')), 'still fine');
    }, tags: 'timing');

    test('forged envelopes never change session state', () async {
      final (sa, hs) = await start(alice, bob);
      final sb = await acceptAs(bob, alice, hs);
      await sb.decrypt(await sa.encrypt(t('hello'), chatId: 'c'), chatId: 'c');
      final before = jsonEncode(sb.toJson());
      final rnd = Random(9);
      Uint8List rand(int n) =>
          Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
      for (var i = 0; i < 5; i++) {
        await expectLater(
          sb.decrypt(
            Envelope(
              n: 0,
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
          throwsA(isA<SessionException>()),
        );
      }
      expect(jsonEncode(sb.toJson()), before);
    });
  });
}

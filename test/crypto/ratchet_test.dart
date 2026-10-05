import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fireplace/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/prekey_helpers.dart';

Uint8List t(String s) => Uint8List.fromList(utf8.encode(s));
String s(List<int> b) => utf8.decode(b);

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

Future<(Session, Session)> pair(Party a, Party b) async {
  final (sa, hs) = await Session.initiate(
    local: a.keys,
    localBundle: a.bundle,
    remote: await b.pk.claim(),
  );
  final sb = await Session.accept(
    local: b.keys,
    localBundle: b.bundle,
    remote: a.bundle,
    handshake: hs,
    signedPreKey: b.pk.spk,
    oneTimePreKey: b.pk.opk,
  );
  return (sa, sb);
}

Session copy(Session x) => Session.fromJson(
  jsonDecode(jsonEncode(x.toJson())) as Map<String, dynamic>,
);

Future<Uint8List> send(Session from, Session to, String text) async {
  final e = await from.encrypt(t(text), chatId: 'c');
  return to.decrypt(e, chatId: 'c');
}

void main() {
  late Party alice, bob;
  setUpAll(() async {
    alice = await Party.create('alice');
    bob = await Party.create('bob');
  });

  test(
    'responder cannot send before it has received; afterwards it can',
    () async {
      final (sa, sb) = await pair(alice, bob);
      expect(sa.canSend, isTrue);
      expect(sb.canSend, isFalse);
      await expectLater(
        sb.encrypt(t('too early'), chatId: 'c'),
        throwsA(isA<SessionException>()),
      );
      await send(sa, sb, 'hi');
      expect(sb.canSend, isTrue);
    },
  );

  test('every change of direction rotates the ratchet keys', () async {
    final (sa, sb) = await pair(alice, bob);
    final seenA = <String>{}, seenB = <String>{};
    for (var i = 0; i < 6; i++) {
      final e1 = await sa.encrypt(t('a$i'), chatId: 'c');
      expect(s(await sb.decrypt(e1, chatId: 'c')), 'a$i');
      seenA.add(b64(e1.rx));
      final e2 = await sb.encrypt(t('b$i'), chatId: 'c');
      expect(s(await sa.decrypt(e2, chatId: 'c')), 'b$i');
      seenB.add(b64(e2.rx));
    }
    expect(seenA.length, 6);
    expect(seenB.length, 6);
    expect(seenA.intersection(seenB), isEmpty);
  });

  test('a long one-sided stream keeps one chain; counters count up; pn is 0 until a reply', () async {
    final (sa, sb) = await pair(alice, bob);
    final rxs = <String>{};
    for (var i = 0; i < 60; i++) {
      final e = await sa.encrypt(t('m$i'), chatId: 'c');
      expect(e.n, i);
      expect(e.pn, 0);
      rxs.add(b64(e.rx));
      expect(s(await sb.decrypt(e, chatId: 'c')), 'm$i');
    }
    expect(rxs.length, 1);
  });

  test('messages of the previous chain arriving after the new chain still decrypt (pn)', () async {
    final (sa, sb) = await pair(alice, bob);
    final a0 = await sa.encrypt(t('a0'), chatId: 'c');
    final a1 = await sa.encrypt(t('a1'), chatId: 'c');
    final a2 = await sa.encrypt(t('a2'), chatId: 'c');
    expect(s(await sb.decrypt(a0, chatId: 'c')), 'a0');
    final b0 = await sb.encrypt(t('b0'), chatId: 'c');
    expect(s(await sa.decrypt(b0, chatId: 'c')), 'b0');
    final a3 = await sa.encrypt(t('a3'), chatId: 'c'); // new chain, pn = 3
    expect(a3.pn, 3);
    expect(
      s(await sb.decrypt(a3, chatId: 'c')),
      'a3',
    ); // a1, a2 still outstanding
    expect(s(await sb.decrypt(a2, chatId: 'c')), 'a2');
    expect(s(await sb.decrypt(a1, chatId: 'c')), 'a1');
    await expectLater(
      sb.decrypt(a1, chatId: 'c'),
      throwsA(isA<SessionException>()),
    );
  });

  test('first message arriving late (a later one first) still works', () async {
    final (sa, sb) = await pair(alice, bob);
    final e0 = await sa.encrypt(t('first'), chatId: 'c');
    final e1 = await sa.encrypt(t('second'), chatId: 'c');
    expect(s(await sb.decrypt(e1, chatId: 'c')), 'second');
    expect(s(await sb.decrypt(e0, chatId: 'c')), 'first');
  });

  group('tampering with any header field fails and leaves state intact', () {
    Future<void> check(String name, Envelope Function(Envelope) f) async {
      final (sa, sb) = await pair(alice, bob);
      final e = await sa.encrypt(t('payload'), chatId: 'c');
      final before = jsonEncode(sb.toJson());
      await expectLater(
        sb.decrypt(f(e), chatId: 'c'),
        throwsA(isA<SessionException>()),
        reason: name,
      );
      expect(jsonEncode(sb.toJson()), before, reason: '$name changed state');
      expect(s(await sb.decrypt(e, chatId: 'c')), 'payload');
    }

    Envelope w(
      Envelope e, {
      int? n,
      int? pn,
      Uint8List? rx,
      Uint8List? rk,
      Uint8List? rc,
    }) => Envelope(
      n: n ?? e.n,
      pn: pn ?? e.pn,
      sid: e.sid,
      rx: rx ?? e.rx,
      rk: rk ?? e.rk,
      rc: rc ?? e.rc,
      nonce: e.nonce,
      ct: e.ct,
      mac: e.mac,
      handshake: e.handshake,
    );
    Uint8List flip(Uint8List b) => Uint8List.fromList(b)..[3] ^= 1;

    test('rx', () => check('rx', (e) => w(e, rx: flip(e.rx))));
    test('rk', () => check('rk', (e) => w(e, rk: flip(e.rk))));
    test('rc', () => check('rc', (e) => w(e, rc: flip(e.rc))));
    test('pn', () => check('pn', (e) => w(e, pn: e.pn + 1)));
    test('n', () => check('n', (e) => w(e, n: e.n + 1)));
  });

  test('replays and cross-session injection fail', () async {
    final (sa, sb) = await pair(alice, bob);
    final e = await sa.encrypt(t('once'), chatId: 'c');
    await sb.decrypt(e, chatId: 'c');
    await expectLater(
      sb.decrypt(e, chatId: 'c'),
      throwsA(isA<SessionException>()),
    );
    final (sa2, _) = await pair(alice, bob);
    final other = await sa2.encrypt(t('x'), chatId: 'c');
    await expectLater(
      sb.decrypt(other, chatId: 'c'),
      throwsA(isA<SessionException>()),
    );
  });

  test('gap limits: too many skipped messages are rejected cheaply', () async {
    final (sa, sb) = await pair(alice, bob);
    final e = await sa.encrypt(t('x'), chatId: 'c');
    final far = Envelope(
      n: Session.maxSkip + 2,
      pn: 0,
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
    expect(s(await sb.decrypt(e, chatId: 'c')), 'x');
  });

  test(
    'state survives JSON round trips at every step of a conversation',
    () async {
      var (sa, sb) = await pair(alice, bob);
      for (var i = 0; i < 8; i++) {
        expect(s(await send(sa, sb, 'a$i')), 'a$i');
        sa = copy(sa);
        sb = copy(sb);
        expect(s(await send(sb, sa, 'b$i')), 'b$i');
        sa = copy(sa);
        sb = copy(sb);
      }
    },
  );

  group('security properties', () {
    test('post-compromise security (receiver stolen): the attacker follows until the victim answers with fresh keys, then is locked out', () async {
      final (sa, sb) = await pair(alice, bob);
      await send(sa, sb, 'a0');
      await send(sb, sa, 'b0');
      await send(sa, sb, 'a1');

      final stolen = copy(sb); // attacker copies Bob's full session state now

      // Messages that still use keys the attacker already holds are readable (unavoidable):
      final m1 = await sa.encrypt(t('m1'), chatId: 'c');
      expect(s(await sb.decrypt(m1, chatId: 'c')), 'm1');
      expect(s(await stolen.decrypt(m1, chatId: 'c')), 'm1');
      final r1 = await sb.encrypt(
        t('r1'),
        chatId: 'c',
      ); // Bob's pre-compromise sending keys
      expect(s(await sa.decrypt(r1, chatId: 'c')), 'r1');
      final m2 = await sa.encrypt(
        t('m2'),
        chatId: 'c',
      ); // Alice targets Bob's old ratchet key
      expect(s(await sb.decrypt(m2, chatId: 'c')), 'm2');
      expect(s(await stolen.decrypt(m2, chatId: 'c')), 'm2');

      // Bob has now generated key pairs the attacker never saw and answers with them.
      final r2 = await sb.encrypt(t('r2'), chatId: 'c');
      expect(s(await sa.decrypt(r2, chatId: 'c')), 'r2');
      // Alice's next chain is derived from those fresh keys: closed to the attacker, forever.
      for (var i = 0; i < 4; i++) {
        final m = await sa.encrypt(t('closed $i'), chatId: 'c');
        expect(s(await sb.decrypt(m, chatId: 'c')), 'closed $i');
        await expectLater(
          stolen.decrypt(m, chatId: 'c'),
          throwsA(isA<SessionException>()),
        );
        final r = await sb.encrypt(t('closed reply $i'), chatId: 'c');
        expect(s(await sa.decrypt(r, chatId: 'c')), 'closed reply $i');
      }
    });

    test('post-compromise security (sender stolen): the attacker can read what the stolen keys reach, then loses the session', () async {
      final (sa, sb) = await pair(alice, bob);
      await send(sa, sb, 'a0');
      await send(sb, sa, 'b0');
      final stolen = copy(sa); // attacker copies Alice's full session state now

      final m1 = await sa.encrypt(t('m1'), chatId: 'c');
      await sb.decrypt(m1, chatId: 'c');
      // Bob answers with a fresh key pair, targeted at Alice's (stolen) current keys:
      final r1 = await sb.encrypt(t('r1'), chatId: 'c');
      expect(s(await sa.decrypt(r1, chatId: 'c')), 'r1');
      expect(s(await stolen.decrypt(r1, chatId: 'c')), 'r1'); // unavoidable
      // Alice now makes fresh keys after the compromise and Bob answers to those.
      final m2 = await sa.encrypt(t('m2'), chatId: 'c');
      await sb.decrypt(m2, chatId: 'c');
      final r2 = await sb.encrypt(t('r2'), chatId: 'c');
      expect(s(await sa.decrypt(r2, chatId: 'c')), 'r2');
      await expectLater(
        stolen.decrypt(r2, chatId: 'c'),
        throwsA(isA<SessionException>()),
      );
      final r3 = await sb.encrypt(t('r3'), chatId: 'c');
      expect(s(await sa.decrypt(r3, chatId: 'c')), 'r3');
      await expectLater(
        stolen.decrypt(r3, chatId: 'c'),
        throwsA(isA<SessionException>()),
      );
    });

    test('forward secrecy: a state copy cannot read messages that were already processed', () async {
      final (sa, sb) = await pair(alice, bob);
      final old = <Envelope>[];
      for (var i = 0; i < 4; i++) {
        final e = await sa.encrypt(t('old $i'), chatId: 'c');
        old.add(e);
        await sb.decrypt(e, chatId: 'c');
      }
      final r = await sb.encrypt(t('reply'), chatId: 'c');
      await sa.decrypt(r, chatId: 'c');
      final e2 = await sa.encrypt(t('old 4'), chatId: 'c');
      old.add(e2);
      await sb.decrypt(e2, chatId: 'c');
      final stolen = copy(sb); // later compromise of Bob
      for (final e in old) {
        await expectLater(
          stolen.decrypt(e, chatId: 'c'),
          throwsA(isA<SessionException>()),
        );
      }
      // the stored state holds no skipped-message keys for processed messages
      expect((stolen.toJson()['st'] as Map)['skipped'], isEmpty);
    });

    test('an old message from a retired chain cannot be replayed to trigger a ratchet', () async {
      final (sa, sb) = await pair(alice, bob);
      final a0 = await sa.encrypt(t('a0'), chatId: 'c');
      await sb.decrypt(a0, chatId: 'c');
      await sa.decrypt(await sb.encrypt(t('b0'), chatId: 'c'), chatId: 'c');
      final a1 = await sa.encrypt(t('a1'), chatId: 'c');
      await sb.decrypt(a1, chatId: 'c');
      final before = jsonEncode(sb.toJson());
      await expectLater(
        sb.decrypt(a0, chatId: 'c'),
        throwsA(isA<SessionException>()),
      );
      expect(jsonEncode(sb.toJson()), before);
    });
  });

  test(
    'randomized conversations with reordering stay consistent (fuzz)',
    () async {
      for (final seed in [1, 2, 3, 4, 5, 6]) {
        final rnd = Random(seed);
        var (a, b) = await pair(alice, bob);
        final inflightToB = <(Envelope, String)>[];
        final inflightToA = <(Envelope, String)>[];
        final delivered = <String>{};
        final sent = <String>{};
        var counter = 0;
        for (var step = 0; step < 90; step++) {
          final action = rnd.nextInt(10);
          if (action < 4) {
            final txt = 'a${counter++}-$seed';
            inflightToB.add((await a.encrypt(t(txt), chatId: 'c'), txt));
            sent.add(txt);
          } else if (action < 6 && b.canSend) {
            final txt = 'b${counter++}-$seed';
            inflightToA.add((await b.encrypt(t(txt), chatId: 'c'), txt));
            sent.add(txt);
          } else if (action < 8 && inflightToB.isNotEmpty) {
            // deliver a random one of the oldest few (bounded reordering)
            final i = rnd.nextInt(min(4, inflightToB.length));
            final (e, txt) = inflightToB.removeAt(i);
            expect(s(await b.decrypt(e, chatId: 'c')), txt);
            delivered.add(txt);
          } else if (inflightToA.isNotEmpty) {
            final i = rnd.nextInt(min(4, inflightToA.length));
            final (e, txt) = inflightToA.removeAt(i);
            expect(s(await a.decrypt(e, chatId: 'c')), txt);
            delivered.add(txt);
          }
          if (rnd.nextInt(12) == 0) {
            a = copy(a);
            b = copy(b);
          }
        }
        for (final (e, txt) in inflightToB) {
          expect(s(await b.decrypt(e, chatId: 'c')), txt);
          delivered.add(txt);
        }
        for (final (e, txt) in inflightToA) {
          expect(s(await a.decrypt(e, chatId: 'c')), txt);
          delivered.add(txt);
        }
        expect(delivered, sent, reason: 'seed $seed');
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

// Randomised protocol simulations for the session layer (handshake + hybrid double ratchet).
//
// Each run drives two parties through a random schedule of sends, reordering, drops,
// duplicate deliveries, replays, reflection (a message handed back to its own sender),
// tampering, and app restarts (session serialised and reloaded), and checks the invariants
// after every step. Runs are seeded, so a failure is reproduced exactly:
//
//   flutter test test/crypto/protocol_property_test.dart --dart-define=PROTOCOL_SEED=<seed>
//   flutter test test/crypto/protocol_property_test.dart --dart-define=PROTOCOL_RUNS=100
//
// Invariants
//   1. A delivered message decrypts to exactly what was sent.
//   2. A message is accepted at most once: any re-delivery is refused.
//   3. Nothing is ever decrypted with the wrong session, chat, direction or peer.
//   4. Tampering with ANY header or ciphertext field is refused, and refusing it leaves the
//      session intact (the genuine message still decrypts afterwards).
//   5. Every message that was not dropped is eventually readable, whatever the order.
//   6. Nonces, and (ratchet key, counter) pairs, are never reused.
//
// These test the logic of the protocol under adversarial scheduling. They are not a proof
// of security; see docs/protocol/threat-model.md.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fireplace/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/prekey_helpers.dart';

const _runs = int.fromEnvironment('PROTOCOL_RUNS', defaultValue: 10);
const _onlySeed = int.fromEnvironment('PROTOCOL_SEED', defaultValue: -1);
const _steps = int.fromEnvironment('PROTOCOL_STEPS', defaultValue: 90);

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

Future<(Session, Session, HandshakeInit)> pair(Party a, Party b) async {
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
  return (sa, sb, hs);
}

Session reload(Session s) => Session.fromJson(
  jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
);

/// The envelope as it would arrive from the server.
Map<String, dynamic> wire(Envelope e) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(e.toJson())) as Map);

Envelope parse(Map<String, dynamic> j) => Envelope.fromJson(j);

/// True if [body] is refused (any of the expected rejection types).
Future<bool> refused(Future<Object?> Function() body) async {
  try {
    await body();
    return false;
  } on SessionException {
    return true;
  } on FormatException {
    return true;
  }
}

class Sent {
  Sent(this.id, this.text, this.fromAlice, this.json);
  final int id;
  final String text;
  final bool fromAlice;
  final Map<String, dynamic> json;
  bool dropped = false;
  bool accepted = false;
}

String flipByte(String b64Value, Random rnd) {
  final bytes = Uint8List.fromList(base64.decode(b64Value));
  bytes[rnd.nextInt(bytes.length)] ^= 1 << rnd.nextInt(8);
  return base64.encode(bytes);
}

/// Mutates one field of a wire envelope; returns what was changed (for failure messages).
String tamper(Map<String, dynamic> j, Random rnd) {
  const bytesFields = ['ct', 'mac', 'nonce', 'rx', 'rk', 'rc'];
  const choices = [...bytesFields, 'n', 'pn', 'sid'];
  final field = choices[rnd.nextInt(choices.length)];
  switch (field) {
    case 'n':
      j['n'] = (j['n'] as int) + 1 + rnd.nextInt(3);
    case 'pn':
      j['pn'] = (j['pn'] as int) + 1 + rnd.nextInt(3);
    case 'sid':
      final sid = j['sid'] as String;
      j['sid'] =
          '${sid.substring(0, sid.length - 1)}${sid.endsWith('A') ? 'B' : 'A'}';
    default:
      j[field] = flipByte(j[field] as String, rnd);
  }
  return field;
}

Future<void> simulate(int seed, Party alice, Party bob) async {
  final rnd = Random(seed);
  var (a, b, _) = await pair(alice, bob);
  final trace = <String>[];
  String why(String m) =>
      'seed $seed, step ${trace.length}: $m\n  trace: ${trace.join(' | ')}';
  Never fail(String m) => throw TestFailure(why(m));

  final all = <Sent>[];
  final toAlice = <Sent>[];
  final toBob = <Sent>[];
  final usedNonces = <String>{};
  final usedCounters = <String>{};
  var tampers =
      0; // kept below the failed-new-chain budget (8 per minute) on purpose

  Session sessionOf(bool alicePart) => alicePart ? a : b;
  void setSession(bool alicePart, Session s) => alicePart ? a = s : b = s;

  Future<void> deliver(Sent m) async {
    final to = !m.fromAlice; // true => Alice receives
    final session = sessionOf(to);
    final Uint8List plain;
    try {
      plain = await session.decrypt(parse(m.json), chatId: 'c');
    } on SessionException catch (e) {
      fail('honest message #${m.id} refused: ${e.message}');
    }
    if (utf8.decode(plain) != m.text) {
      fail('message ${m.id} decrypted to the wrong text');
    }
    if (m.accepted) fail('message ${m.id} was accepted twice');
    m.accepted = true;
  }

  Future<void> expectRefused(
    Sent m, {
    required bool alicePart,
    required String what,
  }) async {
    final ok = await refused(
      () => sessionOf(alicePart).decrypt(parse(m.json), chatId: 'c'),
    );
    if (!ok) fail('$what: message ${m.id} was accepted but must be refused');
  }

  for (var step = 0; step < _steps; step++) {
    final action = rnd.nextInt(100);
    if (action < 34) {
      // send
      final fromAlice = rnd.nextBool();
      final s = sessionOf(fromAlice);
      if (!s.canSend) {
        trace.add('send(${fromAlice ? 'A' : 'B'}:blocked)');
        continue;
      }
      final id = all.length;
      final text = 'm$id-${rnd.nextInt(1 << 30)}';
      final env = await s.encrypt(utf8.encode(text), chatId: 'c');
      final m = Sent(id, text, fromAlice, wire(env));
      if (!usedNonces.add('${m.json['sid']}:${m.json['nonce']}')) {
        fail('nonce reused');
      }
      if (!usedCounters.add(
        '${fromAlice ? 'A' : 'B'}:${m.json['rx']}:${m.json['n']}',
      )) {
        fail('(ratchet key, counter) reused');
      }
      all.add(m);
      (fromAlice ? toBob : toAlice).add(m);
      trace.add('send(${fromAlice ? 'A' : 'B'}#$id)');
    } else if (action < 62) {
      // deliver a random in-flight message (this is where reordering comes from)
      final queue = rnd.nextBool() ? toBob : toAlice;
      if (queue.isEmpty) continue;
      final m = queue.removeAt(rnd.nextInt(queue.length));
      if (rnd.nextInt(10) == 0) {
        m.dropped = true;
        trace.add('drop(#${m.id})');
        continue;
      }
      await deliver(m);
      trace.add('deliver(#${m.id})');
    } else if (action < 72) {
      // replay: a message accepted earlier must be refused now
      final done = all.where((m) => m.accepted).toList();
      if (done.isEmpty) continue;
      final m = done[rnd.nextInt(done.length)];
      await expectRefused(m, alicePart: !m.fromAlice, what: 'replay');
      trace.add('replay(#${m.id})');
    } else if (action < 78) {
      // reflection: hand a message back to its own sender
      if (all.isEmpty) continue;
      final m = all[rnd.nextInt(all.length)];
      await expectRefused(m, alicePart: m.fromAlice, what: 'reflection');
      trace.add('reflect(#${m.id})');
    } else if (action < 84) {
      // wrong chat id: the chat is bound into the encryption
      final inflight = [...toAlice, ...toBob];
      if (inflight.isEmpty || tampers >= 5) continue;
      tampers++;
      final m = inflight[rnd.nextInt(inflight.length)];
      final ok = await refused(
        () =>
            sessionOf(!m.fromAlice)
                .decrypt(parse(m.json), chatId: 'other-chat'),
      );
      if (!ok) fail('message ${m.id} decrypted under a different chat id');
      trace.add('wrongChat(#${m.id})');
    } else if (action < 92) {
      // tamper with an in-flight message; refusing it must not damage the session
      final inflight = [...toAlice, ...toBob];
      if (inflight.isEmpty || tampers >= 5) continue;
      tampers++;
      final m = inflight[rnd.nextInt(inflight.length)];
      final bad = Map<String, dynamic>.from(m.json);
      final field = tamper(bad, rnd);
      final ok = await refused(
        () async => sessionOf(!m.fromAlice).decrypt(parse(bad), chatId: 'c'),
      );
      if (!ok) fail('tampered "$field" of #${m.id} was accepted');
      trace.add('tamper($field of #${m.id})');
    } else {
      // app restart: the session is saved and reloaded
      final alicePart = rnd.nextBool();
      setSession(alicePart, reload(sessionOf(alicePart)));
      trace.add('restart(${alicePart ? 'A' : 'B'})');
    }
  }

  // flush everything still in flight, in a random order
  final rest = [...toAlice, ...toBob]..shuffle(rnd);
  for (final m in rest) {
    await deliver(m);
    trace.add('flush(#${m.id})');
  }
  for (final m in all) {
    if (!m.dropped && !m.accepted) fail('message ${m.id} was never readable');
  }
  // After all that, the conversation must still work in both directions.
  for (final fromAlice in [true, false, true]) {
    final s = sessionOf(fromAlice);
    if (!s.canSend) continue;
    final text = 'final-${rnd.nextInt(1 << 30)}';
    final env = await s.encrypt(utf8.encode(text), chatId: 'c');
    final got = await sessionOf(!fromAlice)
        .decrypt(parse(wire(env)), chatId: 'c');
    if (utf8.decode(got) != text) fail('conversation broken at the end');
  }
}

void main() {
  late Party alice, bob;
  setUpAll(() async {
    alice = await Party.create('alice');
    bob = await Party.create('bob');
  });

  group('random schedules', () {
    final seeds = _onlySeed >= 0
        ? [_onlySeed]
        : [for (var i = 1; i <= _runs; i++) 1000 + i];
    for (final seed in seeds) {
      test(
        'seed $seed',
        () => simulate(seed, alice, bob),
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  });

  group('cheap refusals', () {
    test(
      'replaying or reflecting messages many times never blocks honest traffic',
      () async {
        final (sa, sb, _) = await pair(alice, bob);
        final sent = <Envelope>[];
        // a few turns, so there are several retired chains on both sides
        for (var turn = 0; turn < 4; turn++) {
          for (final from in [sa, sb]) {
            if (!from.canSend) continue;
            final e = await from.encrypt(utf8.encode('t$turn'), chatId: 'c');
            sent.add(e);
            await (identical(from, sa) ? sb : sa).decrypt(e, chatId: 'c');
          }
        }
        // far more than the failure budget (8 per minute) of replays and reflections
        for (var i = 0; i < 40; i++) {
          final e = sent[i % sent.length];
          final fromAlice = e.rx.isNotEmpty && sent.indexOf(e).isEven;
          expect(
            await refused(() => (fromAlice ? sb : sa).decrypt(e, chatId: 'c')),
            isTrue,
          );
          expect(
            await refused(() => (fromAlice ? sa : sb).decrypt(e, chatId: 'c')),
            isTrue,
          );
        }
        // honest new-chain traffic still flows both ways
        for (final from in [sa, sb, sa, sb]) {
          if (!from.canSend) continue;
          final e = await from.encrypt(utf8.encode('after'), chatId: 'c');
          final got = await (identical(from, sa) ? sb : sa).decrypt(
            e,
            chatId: 'c',
          );
          expect(utf8.decode(got), 'after');
        }
      },
    );

    test('retired keys survive a restart and are bounded', () async {
      final (sa, sb, _) = await pair(alice, bob);
      for (var i = 0; i < 6; i++) {
        for (final (from, to) in [(sa, sb), (sb, sa)]) {
          if (!from.canSend) continue;
          await to.decrypt(
            await from.encrypt(utf8.encode('x$i'), chatId: 'c'),
            chatId: 'c',
          );
        }
      }
      final st = reload(sa).toJson()['st'] as Map<String, dynamic>;
      final retired = st['retired'] as List;
      expect(retired, isNotEmpty);
      expect(retired.length, lessThanOrEqualTo(64));
      expect(retired.toSet().length, retired.length, reason: 'no duplicates');
    });
  });

  group('first flight', () {
    test(
      'the responder can start from ANY of the first messages, in any order',
      () async {
        for (var seed = 1; seed <= 6; seed++) {
          final rnd = Random(seed);
          final (sa, hs) = await Session.initiate(
            local: alice.keys,
            localBundle: alice.bundle,
            remote: await bob.pk.claim(),
          );
          final envs = [
            for (var i = 0; i < 4; i++)
              (
                text: 'first-$i',
                e: await sa.encrypt(utf8.encode('first-$i'), chatId: 'c'),
              ),
          ];
          // every message of the first flight carries the handshake until the peer answers
          for (final x in envs) {
            expect(x.e.handshake, isNotNull, reason: 'seed $seed');
          }
          final order = [...envs]..shuffle(rnd);
          final sb = await Session.accept(
            local: bob.keys,
            localBundle: bob.bundle,
            remote: alice.bundle,
            handshake: order.first.e.handshake!,
            signedPreKey: bob.pk.spk,
            oneTimePreKey: bob.pk.opk,
          );
          expect(
            sb.sessionId,
            sa.sessionId,
            reason: 'both sides agree on the session id',
          );
          for (final x in order) {
            expect(
              utf8.decode(await sb.decrypt(x.e, chatId: 'c')),
              x.text,
              reason: 'seed $seed',
            );
          }
          for (final x in order) {
            expect(
              await refused(() => sb.decrypt(x.e, chatId: 'c')),
              isTrue,
              reason: 'replay of ${x.text}, seed $seed',
            );
          }
        }
      },
    );

    test(
      'a handshake bound to one peer/prekey cannot be accepted for another',
      () async {
        final carol = await Party.create('carol');
        final (_, sb, hs) = await pair(alice, bob);
        // Carol (a different device with different prekeys) cannot accept Bob's handshake.
        expect(
          await refused(
            () => Session.accept(
              local: carol.keys,
              localBundle: carol.bundle,
              remote: alice.bundle,
              handshake: hs,
              signedPreKey: carol.pk.spk,
              oneTimePreKey: carol.pk.opk,
            ),
          ),
          isTrue,
        );
        // Bob cannot accept it while believing it came from someone else.
        expect(
          await refused(
            () => Session.accept(
              local: bob.keys,
              localBundle: bob.bundle,
              remote: carol.bundle,
              handshake: hs,
              signedPreKey: bob.pk.spk,
              oneTimePreKey: bob.pk.opk,
            ),
          ).then((r) async {
            // Accepting "from carol" may construct a session, but it must not be able to read
            // Alice's messages: the session id and keys differ.
            if (r) return true;
            final fake = await Session.accept(
              local: bob.keys,
              localBundle: bob.bundle,
              remote: carol.bundle,
              handshake: hs,
              signedPreKey: bob.pk.spk,
              oneTimePreKey: bob.pk.opk,
            );
            return fake.sessionId != sb.sessionId;
          }),
          isTrue,
        );
      },
    );
  });
}

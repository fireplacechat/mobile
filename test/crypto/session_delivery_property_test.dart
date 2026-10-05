import 'dart:convert';
import 'dart:math';

import 'package:fireplace/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/prekey_helpers.dart';

class _Peer {
  _Peer(this.keys, this.bundle, this.pk);
  final DeviceKeys keys;
  final DeviceBundle bundle;
  final PreKeyed pk;

  static Future<_Peer> create(String uid) async {
    final identity = await AccountIdentity.generate();
    final keys = await DeviceKeys.generate();
    final bundle = await keys.certify(identity, uid);
    return _Peer(keys, bundle, await preKeyed(bundle, identity));
  }
}

Future<(Session, Session)> _sessions() async {
  final alice = await _Peer.create('alice');
  final bob = await _Peer.create('bob');
  final (send, hs) = await Session.initiate(
    local: alice.keys,
    localBundle: alice.bundle,
    remote: await bob.pk.claim(),
  );
  final receive = await Session.accept(
    local: bob.keys,
    localBundle: bob.bundle,
    remote: alice.bundle,
    handshake: hs,
    signedPreKey: bob.pk.spk,
    oneTimePreKey: bob.pk.opk,
  );
  return (send, receive);
}

void main() {
  test('failed authentication leaves an out-of-order key available', () async {
    final (send, receive) = await _sessions();
    final first = await send.encrypt(utf8.encode('first'), chatId: 'alice_bob');
    final second = await send.encrypt(
      utf8.encode('second'),
      chatId: 'alice_bob',
    );
    await receive.decrypt(second, chatId: 'alice_bob');

    final wire = Map<String, dynamic>.from(first.toJson());
    final ciphertext = base64.decode(wire['ct'] as String)..[0] ^= 1;
    wire['ct'] = base64.encode(ciphertext);
    final corrupt = Envelope.fromJson(wire);
    await expectLater(
      receive.decrypt(corrupt, chatId: 'alice_bob'),
      throwsA(isA<SessionException>()),
    );
    expect(
      utf8.decode(await receive.decrypt(first, chatId: 'alice_bob')),
      'first',
    );
  });

  test('shuffled delivery, drops, and duplicates preserve ratchet state', () async {
    final (send, receive) = await _sessions();
    const count = 80;
    final envelopes = [
      for (var i = 0; i < count; i++)
        await send.encrypt(utf8.encode('message-$i'), chatId: 'alice_bob'),
    ];

    // Simulate drops, then deliver the rest in repeatable pseudo-random order.
    final delivered = [for (var i = 2; i < count; i++) i];
    delivered.shuffle(Random(0xF1E));
    final consumed = <int>{};
    for (final index in delivered) {
      final plaintext = await receive.decrypt(
        envelopes[index],
        chatId: 'alice_bob',
      );
      expect(utf8.decode(plaintext), 'message-$index');
      consumed.add(index);

      if (index % 7 == 0) {
        await expectLater(
          receive.decrypt(envelopes[index], chatId: 'alice_bob'),
          throwsA(isA<SessionException>()),
        );
      }
    }

    expect(consumed, hasLength(count - 2));
    expect(
      utf8.decode(await receive.decrypt(envelopes[0], chatId: 'alice_bob')),
      'message-0',
    );
    expect(
      utf8.decode(await receive.decrypt(envelopes[1], chatId: 'alice_bob')),
      'message-1',
    );
    await expectLater(
      receive.decrypt(envelopes[0], chatId: 'alice_bob'),
      throwsA(isA<SessionException>()),
    );
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pqcrypto/pqcrypto.dart';
import 'package:fireplace/src/crypto/codec.dart' show lp, concat, utf8Bytes;

import 'package:fireplace/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/prekey_helpers.dart';

void main() {
  for (final value in [0, 1]) {
    test('link sealing rejects low-order X25519 point $value', () async {
      final identity = await AccountIdentity.generate();
      final device = await DeviceKeys.generate();
      final lowOrder = Uint8List(32)..[0] = value;
      await expectLater(
        LinkCrypto.seal(
          identity,
          uid: 'alice',
          deviceId: device.deviceId,
          x25519Pub: lowOrder,
          kemPub: device.kemPub,
        ),
        throwsA(isA<LinkException>()),
      );
    });
  }

  test(
    'session initiation rejects an authenticated low-order signed prekey',
    () async {
      final alice = await AccountIdentity.generate();
      final bob = await AccountIdentity.generate();
      final a = await DeviceKeys.generate();
      final b = await DeviceKeys.generate();
      final ab = await a.certify(alice, 'alice');
      final bb = await b.certify(bob, 'bob');
      final pk = await preKeyed(bb, bob);
      final normal = (await pk.claim()).signed;
      final low = Uint8List(32);
      final signed = PublishedPreKey(
        id: normal.id,
        kind: normal.kind,
        x25519Pub: low,
        kemPub: normal.kemPub,
        sig: await bob.sign(
          PreKeys.signedMessage(
            'bob',
            b.deviceId,
            normal.id,
            low,
            normal.kemPub,
          ),
        ),
      );
      expect(await PreKeys.verifySigned(bb, signed), isTrue);
      await expectLater(
        Session.initiate(
          local: a,
          localBundle: ab,
          remote: PreKeyBundle(device: bb, signed: signed),
        ),
        throwsA(isA<SessionException>()),
      );
    },
  );

  test('session acceptance rejects a low-order handshake ephemeral', () async {
    final alice = await AccountIdentity.generate();
    final bob = await AccountIdentity.generate();
    final a = await DeviceKeys.generate();
    final b = await DeviceKeys.generate();
    final ab = await a.certify(alice, 'alice');
    final bb = await b.certify(bob, 'bob');
    final pk = await preKeyed(bb, bob);
    final (_, hs) = await Session.initiate(
      local: a,
      localBundle: ab,
      remote: await pk.claim(),
    );
    await expectLater(
      Session.accept(
        local: b,
        localBundle: bb,
        remote: ab,
        signedPreKey: pk.spk,
        oneTimePreKey: pk.opk,
        handshake: HandshakeInit(
          ek: Uint8List(32),
          kemCt: hs.kemCt,
          spkId: hs.spkId,
          opkId: hs.opkId,
          opkKemCt: hs.opkKemCt,
        ),
      ),
      throwsA(isA<SessionException>()),
    );
  });
  test(
    'link opening rejects an otherwise authentic zero-contribution transfer',
    () async {
      final identity = await AccountIdentity.generate();
      final device = await DeviceKeys.generate();
      final ek = Uint8List(32);
      final (ct, ss) = PqcKem.kyber768.encapsulate(device.kemPub);
      final info = lp([
        utf8Bytes('fireplace/v1/link'),
        utf8Bytes('alice'),
        utf8Bytes(device.deviceId),
        ek,
        ct,
        device.x25519Pub,
        device.kemPub,
      ]);
      final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(concat([Uint8List(32), ss])),
        nonce: const [],
        info: info,
      );
      final box = await AesGcm.with256bits().encrypt(
        utf8.encode(jsonEncode(identity.toJson())),
        secretKey: key,
        aad: info,
      );
      final sealed = SealedIdentity(
        ek: ek,
        kemCt: ct,
        nonce: Uint8List.fromList(box.nonce),
        ct: Uint8List.fromList(box.cipherText),
        mac: Uint8List.fromList(box.mac.bytes),
      );
      await expectLater(
        LinkCrypto.open(sealed, uid: 'alice', keys: device),
        throwsA(isA<LinkException>()),
      );
    },
  );

  test(
    'rejected low-order ratchet leaves state intact and valid delivery works',
    () async {
      final alice = await AccountIdentity.generate();
      final bob = await AccountIdentity.generate();
      final a = await DeviceKeys.generate();
      final b = await DeviceKeys.generate();
      final ab = await a.certify(alice, 'alice');
      final bb = await b.certify(bob, 'bob');
      final pk = await preKeyed(bb, bob);
      final (sender, hs) = await Session.initiate(
        local: a,
        localBundle: ab,
        remote: await pk.claim(),
      );
      final receiver = await Session.accept(
        local: b,
        localBundle: bb,
        remote: ab,
        handshake: hs,
        signedPreKey: pk.spk,
        oneTimePreKey: pk.opk,
      );
      final valid = await sender.encrypt(
        Uint8List.fromList([1, 2, 3]),
        chatId: 'c',
      );
      final before = jsonEncode(receiver.toJson());
      final bad = Envelope.fromJson({
        ...valid.toJson(),
        'rx': b64(Uint8List(32)),
      });
      await expectLater(
        receiver.decrypt(bad, chatId: 'c'),
        throwsA(isA<SessionException>()),
      );
      expect(jsonEncode(receiver.toJson()), before);
      expect(await receiver.decrypt(valid, chatId: 'c'), [1, 2, 3]);
    },
  );
}

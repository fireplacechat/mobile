import 'dart:typed_data';

import '../support/crypto_backend.dart';

import 'package:flutter_test/flutter_test.dart';

void main() => bothCryptoBackends(() {
  group('RecoveryKey', () {
    test(
      'display/parse round trip, formatting tolerant, typos rejected',
      () async {
        final k = RecoveryKey.generate();
        final shown = await k.display();
        expect(
          RegExp(r'^([A-Z2-7]{4}-){8}[A-Z2-7]{4}$').hasMatch(shown),
          isTrue,
          reason: shown,
        );
        for (final variant in [
          shown,
          shown.toLowerCase(),
          shown.replaceAll('-', ' '),
          '  $shown  ',
          shown.replaceAll('-', ''),
        ]) {
          final p = await RecoveryKey.parse(variant);
          expect(p, isNotNull, reason: variant);
          expect(p!.bytes, k.bytes);
        }
        // single-character typo anywhere is caught by the checksum
        final chars = shown.split('');
        for (var i = 0; i < chars.length; i++) {
          if (chars[i] == '-') continue;
          final alt = List<String>.from(chars);
          alt[i] = chars[i] == 'A' ? 'B' : 'A';
          expect(
            await RecoveryKey.parse(alt.join()),
            isNull,
            reason: 'typo at $i',
          );
        }
        expect(await RecoveryKey.parse('too short'), isNull);
        expect(await RecoveryKey.parse('1' * 36), isNull);
      },
    );

    test('keys are unique', () async {
      expect(
        (await RecoveryKey.generate().display()) ==
            (await RecoveryKey.generate().display()),
        isFalse,
      );
    });

    test('backup encrypts the identity; right key restores, wrong key / tamper fail', () async {
      final id = await AccountIdentity.generate();
      final key = RecoveryKey.generate();
      final blob = await RecoveryBackup.encrypt(id, key);
      expect(blob.contains(b64(id.edPub)), isFalse);
      final back = await RecoveryBackup.decrypt(blob, key);
      expect(back.publicBytes, id.publicBytes);
      final sig = await back.sign(Uint8List.fromList([1, 2, 3]));
      expect(
        await AccountIdentity.verify(id.publicBytes, [1, 2, 3], sig),
        isTrue,
      );
      await expectLater(
        RecoveryBackup.decrypt(blob, RecoveryKey.generate()),
        throwsA(isA<BackupException>()),
      );
      final raw = unb64(blob)..[20] ^= 1;
      await expectLater(
        RecoveryBackup.decrypt(b64(raw), key),
        throwsA(isA<BackupException>()),
      );
      await expectLater(
        RecoveryBackup.decrypt('not base64!!', key),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('LinkCrypto', () {
    test('identity is sealed to the new device only', () async {
      final id = await AccountIdentity.generate();
      final newDev = await DeviceKeys.generate();
      final secret = LinkCrypto.newSecret();
      final sealed = await LinkCrypto.seal(
        id,
        uid: 'alice',
        deviceId: newDev.deviceId,
        x25519Pub: newDev.x25519Pub,
        kemPub: newDev.kemPub,
        secret: secret,
      );
      final json = sealed.toJson();
      expect(json.values.join().contains(b64(id.edPub)), isFalse);
      final got = await LinkCrypto.open(
        SealedIdentity.fromJson(json),
        uid: 'alice',
        keys: newDev,
        secret: secret,
      );
      expect(got.publicBytes, id.publicBytes);

      // Everything right except the secret from the QR code.
      for (final wrong in [
        Uint8List.fromList(secret)..[0] ^= 1,
        Uint8List(16),
        Uint8List.fromList([...secret, 0]),
        Uint8List(0),
      ]) {
        await expectLater(
          LinkCrypto.open(sealed, uid: 'alice', keys: newDev, secret: wrong),
          throwsA(isA<LinkException>()),
        );
      }

      final other = await DeviceKeys.generate();
      await expectLater(
        LinkCrypto.open(sealed, uid: 'alice', keys: other, secret: secret),
        throwsA(isA<LinkException>()),
      );
      await expectLater(
        LinkCrypto.open(sealed, uid: 'mallory', keys: newDev, secret: secret),
        throwsA(isA<LinkException>()),
      );
      final bad = SealedIdentity(
        ek: sealed.ek,
        kemCt: sealed.kemCt,
        nonce: sealed.nonce,
        ct: Uint8List.fromList(sealed.ct)..[0] ^= 1,
        mac: sealed.mac,
      );
      await expectLater(
        LinkCrypto.open(bad, uid: 'alice', keys: newDev, secret: secret),
        throwsA(isA<LinkException>()),
      );
    });

    test('the fingerprint depends on the device keys', () async {
      final d = await DeviceKeys.generate();
      final d2 = await DeviceKeys.generate();
      expect(
        await LinkCrypto.requestFingerprint(d.x25519Pub, d.kemPub),
        isNot(await LinkCrypto.requestFingerprint(d2.x25519Pub, d2.kemPub)),
      );
    });
  });
});

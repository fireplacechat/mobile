import 'dart:convert';

import 'package:fireplace/fireplace_crypto.dart' as dart;
import 'package:fireplace_native/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/crypto_backend.dart' show nativeCrypto;

void main() {
  test(
    'hybrid signatures, identities, certificates, and prekeys cross both ways',
    () async {
      final message = utf8.encode('fictional cross-signature probe');
      final dartIdentity = await dart.AccountIdentity.generate();
      final rustJson = nativeCrypto.identityGenerate();
      final rustIdentity = dart.AccountIdentity.fromJson(rustJson);
      final dartSignature = await dartIdentity.sign(message);
      expect(
        nativeCrypto.identityVerify(
          dartIdentity.publicBytes,
          message,
          dartSignature,
        ),
        isTrue,
      );
      final rustSignature = nativeCrypto.identitySign(rustJson, message);
      expect(
        await dart.AccountIdentity.verify(
          rustIdentity.publicBytes,
          message,
          rustSignature,
        ),
        isTrue,
      );
      expect(
        nativeCrypto.fingerprint(dartIdentity.publicBytes),
        await dart.identityFingerprint(dartIdentity.publicBytes),
      );
      expect(
        nativeCrypto.safetyNumber(
          dartIdentity.publicBytes,
          rustIdentity.publicBytes,
        ),
        await dart.safetyNumber(
          dartIdentity.publicBytes,
          rustIdentity.publicBytes,
        ),
      );
      final rustDevice = nativeCrypto.deviceGenerate();
      final device = dart.DeviceKeys.fromJson(rustDevice);
      final cert = nativeCrypto.deviceCertify(
        rustDevice,
        dartIdentity.toJson(),
        'alice',
      );
      final bundle = dart.DeviceBundle(
        uid: 'alice',
        deviceId: device.deviceId,
        x25519Pub: device.x25519Pub,
        kemPub: device.kemPub,
        identityPub: dart.unb64(cert['identityPub']),
        cert: dart.unb64(cert['cert']),
      );
      expect(await bundle.verifyCert(), isTrue);
      final prekey = nativeCrypto.prekeyGenerate(1700000000000);
      final published = nativeCrypto.prekeySign(
        prekey,
        dartIdentity.toJson(),
        'alice',
        device.deviceId,
      );
      expect(
        await dart.PreKeys.verifySigned(
          bundle,
          dart.PublishedPreKey.fromFirestore(
            published['id'] as String,
            published,
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'recovery backups and linking transfers open across both implementations',
    () async {
      final identity = await dart.AccountIdentity.generate();
      final key = dart.RecoveryKey.generate();
      final fromDart = await dart.RecoveryBackup.encrypt(identity, key);
      final openedRust = nativeCrypto.recoveryDecrypt(fromDart, key.bytes);
      expect(jsonEncode(openedRust) == jsonEncode(identity.toJson()), isTrue);
      final fromRust = nativeCrypto.recoveryEncrypt(
        identity.toJson(),
        key.bytes,
      );
      expect(
        (await dart.RecoveryBackup.decrypt(fromRust, key)).publicBytes,
        identity.publicBytes,
      );
      final rustKey = nativeCrypto.recoveryGenerate();
      final parsed = await dart.RecoveryKey.parse(
        nativeCrypto.recoveryDisplay(rustKey),
      );
      expect(parsed!.bytes, rustKey);
      expect(nativeCrypto.recoveryParse(await key.display()), key.bytes);

      final device = await dart.DeviceKeys.generate();
      final sealedDart = await dart.LinkCrypto.seal(
        identity,
        uid: 'alice',
        deviceId: device.deviceId,
        x25519Pub: device.x25519Pub,
        kemPub: device.kemPub,
      );
      final opened = nativeCrypto.linkOpen(
        sealedDart.toJson(),
        'alice',
        device.toJson(),
      );
      expect(jsonEncode(opened) == jsonEncode(identity.toJson()), isTrue);
      final sealedRust = nativeCrypto.linkSeal(
        identity.toJson(),
        'alice',
        device.deviceId,
        device.x25519Pub,
        device.kemPub,
      );
      expect(
        (await dart.LinkCrypto.open(
          dart.SealedIdentity.fromJson(sealedRust),
          uid: 'alice',
          keys: device,
        )).publicBytes,
        identity.publicBytes,
      );
      expect(
        nativeCrypto.linkConfirmation(
          identity.publicBytes,
          device.x25519Pub,
          device.kemPub,
        ),
        await dart.LinkCrypto.confirmationCode(
          identity.publicBytes,
          device.x25519Pub,
          device.kemPub,
        ),
      );
    },
  );
}

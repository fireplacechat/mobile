import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqcrypto/pqcrypto.dart';

void main() {
  test(
    'ML-KEM-768 round trip + tamper -> different secret (implicit rejection)',
    () {
      final (pk, sk) = PqcKem.kyber768.generateKeyPair();
      expect(pk.length, 1184);
      final (ct, ss) = PqcKem.kyber768.encapsulate(pk);
      expect(ct.length, 1088);
      expect(PqcKem.kyber768.decapsulate(sk, ct), ss);
      final bad = ct.sublist(0)..[0] ^= 1;
      expect(PqcKem.kyber768.decapsulate(sk, bad), isNot(ss));
    },
  );

  test('X25519 + HKDF + AES-256-GCM available', () async {
    final x = X25519();
    final a = await x.newKeyPair(), b = await x.newKeyPair();
    final s1 = await x.sharedSecretKey(
      keyPair: a,
      remotePublicKey: await b.extractPublicKey(),
    );
    final s2 = await x.sharedSecretKey(
      keyPair: b,
      remotePublicKey: await a.extractPublicKey(),
    );
    expect(await s1.extractBytes(), await s2.extractBytes());
    final key = await Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    ).deriveKey(secretKey: s1, nonce: const [], info: [1]);
    final aead = AesGcm.with256bits();
    final box = await aead.encrypt([1, 2, 3], secretKey: key, aad: [9]);
    expect(await aead.decrypt(box, secretKey: key, aad: [9]), [1, 2, 3]);
    expect(
      () => aead.decrypt(box, secretKey: key, aad: [8]),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}

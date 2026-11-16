import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pqcrypto/pqcrypto.dart';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/crypto/contributory.dart';
import 'package:fireplace/src/crypto/device.dart';
import 'package:fireplace/src/crypto/identity.dart';

class LinkException implements Exception {
  LinkException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The account identity encrypted to a new device's public keys (hybrid X25519 + ML-KEM-768).
class SealedIdentity {
  SealedIdentity({
    required this.ek,
    required this.kemCt,
    required this.nonce,
    required this.ct,
    required this.mac,
  });
  final Uint8List ek, kemCt, nonce, ct, mac;

  Map<String, String> toJson() => {
    'ek': b64(ek),
    'kemCt': b64(kemCt),
    'nonce': b64(nonce),
    'ct': b64(ct),
    'mac': b64(mac),
  };

  factory SealedIdentity.fromJson(Map<String, dynamic> j) => SealedIdentity(
    ek: unb64(j['ek']),
    kemCt: unb64(j['kemCt']),
    nonce: unb64(j['nonce']),
    ct: unb64(j['ct']),
    mac: unb64(j['mac']),
  );
}

/// Moves the account identity to a new device of the same account.
/// Authenticity does not come from the server. The new device's QR code holds
/// a fingerprint of its public keys, so the server can't swap them, and a
/// random secret that is sent nowhere and goes into the sealing key, so only
/// a device that read the QR code can make a response the new device opens.
class LinkCrypto {
  /// Bytes of secret a new device puts in its QR code.
  static const secretLength = 16;
  static const _secretMax = 64;

  static void _checkSecret(List<int> secret) {
    if (secret.length < secretLength || secret.length > _secretMax) {
      throw LinkException('Invalid device linking secret.');
    }
  }

  static final _x = X25519();
  static final _aead = AesGcm.with256bits();

  /// Fingerprint of the new device's public keys, put in the QR code.
  static Future<String> requestFingerprint(
    List<int> x25519Pub,
    List<int> kemPub,
  ) async {
    final h = (await Sha256().hash(
      lp([utf8Bytes('fireplace/v1/link-fp'), x25519Pub, kemPub]),
    )).bytes;
    return b64(h.sublist(0, 16))
        .replaceAll('+', '-')
        .replaceAll('/', '_')
        .replaceAll('=', '');
  }

  static Uint8List _info(
    String uid,
    String deviceId,
    List<int> ek,
    List<int> kemCt,
    List<int> x25519Pub,
    List<int> kemPub,
  ) => lp([
    utf8Bytes('fireplace/v2/link'),
    utf8Bytes(uid),
    utf8Bytes(deviceId),
    ek,
    kemCt,
    x25519Pub,
    kemPub,
  ]);

  // Both shared secrets have fixed lengths, so the QR secret after them needs
  // no length prefix.
  static Future<SecretKey> _key(
    List<int> dh,
    List<int> ss,
    List<int> secret,
    Uint8List info,
  ) {
    if (!isContributoryX25519Secret(dh)) {
      throw LinkException('Invalid device linking key.');
    }
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(concat([dh, ss, secret])),
      nonce: const <int>[],
      info: info,
    );
  }

  static Future<SealedIdentity> seal(
    AccountIdentity identity, {
    required String uid,
    required String deviceId,
    required Uint8List x25519Pub,
    required Uint8List kemPub,
    required List<int> secret,
  }) async {
    _checkSecret(secret);
    final ekSeed = takeTestBytes(32);
    final ek = ekSeed == null
        ? await _x.newKeyPair()
        : await _x.newKeyPairFromSeed(ekSeed);
    final ekPub = Uint8List.fromList((await ek.extractPublicKey()).bytes);
    final dh = await (await _x.sharedSecretKey(
      keyPair: ek,
      remotePublicKey: SimplePublicKey(x25519Pub, type: KeyPairType.x25519),
    )).extractBytes();
    final coins = takeTestBytes(32);
    final (kemCt, ss) = coins == null
        ? PqcKem.kyber768.encapsulate(kemPub)
        : PqcKem.kyber768.encapsulate(kemPub, coins);
    final info = _info(uid, deviceId, ekPub, kemCt, x25519Pub, kemPub);
    final box = await _aead.encrypt(
      utf8.encode(jsonEncode(identity.toJson())),
      secretKey: await _key(dh, ss, secret, info),
      nonce: takeTestBytes(12),
      aad: info,
    );
    return SealedIdentity(
      ek: ekPub,
      kemCt: kemCt,
      nonce: Uint8List.fromList(box.nonce),
      ct: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  static Future<AccountIdentity> open(
    SealedIdentity s, {
    required String uid,
    required DeviceKeys keys,
    required List<int> secret,
  }) async {
    try {
      _checkSecret(secret);
      final kp = await _x.newKeyPairFromSeed(keys.x25519Seed);
      final dh = await (await _x.sharedSecretKey(
        keyPair: kp,
        remotePublicKey: SimplePublicKey(s.ek, type: KeyPairType.x25519),
      )).extractBytes();
      final ss = PqcKem.kyber768.decapsulate(keys.kemSecret, s.kemCt);
      final info = _info(
        uid,
        keys.deviceId,
        s.ek,
        s.kemCt,
        keys.x25519Pub,
        keys.kemPub,
      );
      final plain = await _aead.decrypt(
        SecretBox(s.ct, nonce: s.nonce, mac: Mac(s.mac)),
        secretKey: await _key(dh, ss, secret, info),
        aad: info,
      );
      return AccountIdentity.fromJson(
        Map<String, dynamic>.from(jsonDecode(utf8.decode(plain))),
      );
    } catch (_) {
      throw LinkException('Could not decrypt the transferred identity.');
    }
  }
}

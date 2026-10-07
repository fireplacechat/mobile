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
/// Authenticity does not come from the server: the new device's public keys
/// travel in a QR code (so the server can't swap them), and a short confirmation
/// code derived from the transferred identity is compared by the user (so the
/// server can't swap the identity).
class LinkCrypto {
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

  /// 6-digit code both devices display; the user checks they match.
  static Future<String> confirmationCode(
    List<int> identityPub,
    List<int> x25519Pub,
    List<int> kemPub,
  ) async {
    final h = (await Sha256().hash(
      lp([utf8Bytes('fireplace/v1/link-sas'), identityPub, x25519Pub, kemPub]),
    )).bytes;
    final n =
        ByteData.sublistView(Uint8List.fromList(h)).getUint32(0) % 1000000;
    return n.toString().padLeft(6, '0');
  }

  static Uint8List _info(
    String uid,
    String deviceId,
    List<int> ek,
    List<int> kemCt,
    List<int> x25519Pub,
    List<int> kemPub,
  ) => lp([
    utf8Bytes('fireplace/v1/link'),
    utf8Bytes(uid),
    utf8Bytes(deviceId),
    ek,
    kemCt,
    x25519Pub,
    kemPub,
  ]);

  static Future<SecretKey> _key(List<int> dh, List<int> ss, Uint8List info) {
    if (!isContributoryX25519Secret(dh)) {
      throw LinkException('Invalid device linking key.');
    }
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(concat([dh, ss])),
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
  }) async {
    final ek = await _x.newKeyPair();
    final ekPub = Uint8List.fromList((await ek.extractPublicKey()).bytes);
    final dh = await (await _x.sharedSecretKey(
      keyPair: ek,
      remotePublicKey: SimplePublicKey(x25519Pub, type: KeyPairType.x25519),
    )).extractBytes();
    final (kemCt, ss) = PqcKem.kyber768.encapsulate(kemPub);
    final info = _info(uid, deviceId, ekPub, kemCt, x25519Pub, kemPub);
    final box = await _aead.encrypt(
      utf8.encode(jsonEncode(identity.toJson())),
      secretKey: await _key(dh, ss, info),
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
  }) async {
    try {
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
        secretKey: await _key(dh, ss, info),
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

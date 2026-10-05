import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pqcrypto/pqcrypto.dart';

import 'codec.dart';
import 'identity.dart';
import 'key_checks.dart';

/// Public, server-visible description of one device. Matches the Firestore
/// `users/{uid}/devices/{deviceId}` document (`sigPub` holds the account identity).
class DeviceBundle {
  DeviceBundle({
    required this.uid,
    required this.deviceId,
    required this.x25519Pub,
    required this.kemPub,
    required this.identityPub,
    required this.cert,
  });

  final String uid;
  final String deviceId;
  final Uint8List x25519Pub;
  final Uint8List kemPub;
  final Uint8List identityPub;
  final Uint8List cert;

  static Uint8List certMessage(
    String uid,
    String deviceId,
    List<int> x25519Pub,
    List<int> kemPub,
  ) => lp([
    utf8Bytes('fireplace/v1/device-cert'),
    utf8Bytes(uid),
    utf8Bytes(deviceId),
    x25519Pub,
    kemPub,
  ]);

  /// True iff the account identity signed exactly these device keys for this uid/device.
  /// Callers must ALSO check [identityPub] against the identity they have pinned/verified.
  Future<bool> verifyCert() => AccountIdentity.verify(
    identityPub,
    certMessage(uid, deviceId, x25519Pub, kemPub),
    cert,
  );

  Map<String, String> toFirestore() => {
    'x25519Pub': b64(x25519Pub),
    'kemPub': b64(kemPub),
    'sigPub': b64(identityPub),
    'deviceCert': b64(cert),
  };

  factory DeviceBundle.fromFirestore(
    String uid,
    String deviceId,
    Map<String, dynamic> d,
  ) => DeviceBundle(
    uid: uid,
    deviceId: deviceId,
    x25519Pub: unb64(d['x25519Pub']),
    kemPub: unb64(d['kemPub']),
    identityPub: unb64(d['sigPub']),
    cert: unb64(d['deviceCert']),
  );
}

/// Private + public key material for this device (X25519 + ML-KEM-768).
class DeviceKeys {
  DeviceKeys._(
    this.deviceId,
    this.x25519Seed,
    this.x25519Pub,
    this.kemPub,
    this.kemSecret,
  );

  final String deviceId;
  final Uint8List x25519Seed;
  final Uint8List x25519Pub;
  final Uint8List kemPub;
  final Uint8List kemSecret;

  static Future<DeviceKeys> generate() async {
    final seed = randomBytes(32);
    final kp = await X25519().newKeyPairFromSeed(seed);
    final pub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    final (kemPk, kemSk) = PqcKem.kyber768.generateKeyPair();
    // 16 random bytes -> 22 url-safe chars, matches the Firestore rules id pattern.
    final id = b64(randomBytes(16))
        .replaceAll('+', '-')
        .replaceAll('/', '_')
        .replaceAll('=', '');
    return DeviceKeys._(id, seed, pub, kemPk, kemSk);
  }

  Future<DeviceBundle> certify(AccountIdentity identity, String uid) async {
    final cert = await identity.sign(
      DeviceBundle.certMessage(uid, deviceId, x25519Pub, kemPub),
    );
    return DeviceBundle(
      uid: uid,
      deviceId: deviceId,
      x25519Pub: x25519Pub,
      kemPub: kemPub,
      identityPub: identity.publicBytes,
      cert: cert,
    );
  }

  Map<String, String> toJson() => {
    'deviceId': deviceId,
    'x25519Seed': b64(x25519Seed),
    'x25519Pub': b64(x25519Pub),
    'kemPub': b64(kemPub),
    'kemSecret': b64(kemSecret),
  };

  /// Strict loader: throws [FormatException] on wrong types or lengths.
  factory DeviceKeys.fromJson(Map<String, dynamic> j) {
    Uint8List b(String k, int len) {
      final v = j[k];
      if (v is! String || v.length > len * 2) throw FormatException('bad $k');
      final out = unb64(v);
      if (out.length != len) throw FormatException('bad $k length');
      return out;
    }

    final id = j['deviceId'];
    if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(id)) {
      throw const FormatException('bad deviceId');
    }
    return DeviceKeys._(
      id,
      b('x25519Seed', 32),
      b('x25519Pub', 32),
      b('kemPub', 1184),
      b('kemSecret', 2400),
    );
  }

  /// True iff each public key belongs to its private half.
  Future<bool> consistent() async =>
      await KeyChecks.x25519Matches(x25519Seed, x25519Pub) &&
      KeyChecks.mlKem768Matches(kemSecret, kemPub);
}

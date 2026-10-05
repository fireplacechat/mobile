import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pqcrypto/pqcrypto.dart';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/crypto/device.dart';
import 'package:fireplace/src/crypto/identity.dart';
import 'package:fireplace/src/crypto/key_checks.dart';

/// Private + public half of one prekey (X25519 + ML-KEM-768). Kept only on the device.
class PreKeyRecord {
  PreKeyRecord({
    required this.id,
    required this.x25519Seed,
    required this.x25519Pub,
    required this.kemSecret,
    required this.kemPub,
    required this.createdAt,
  });

  final String id;
  final Uint8List x25519Seed, x25519Pub, kemSecret, kemPub;
  final DateTime createdAt;

  static Future<PreKeyRecord> generate({DateTime? now}) async {
    final seed = randomBytes(32);
    final kp = await X25519().newKeyPairFromSeed(seed);
    final pub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    final (kemPk, kemSk) = PqcKem.kyber768.generateKeyPair();
    final id = b64(randomBytes(9))
        .replaceAll('+', '-')
        .replaceAll('/', '_'); // 12 url-safe chars
    return PreKeyRecord(
      id: id,
      x25519Seed: seed,
      x25519Pub: pub,
      kemSecret: kemSk,
      kemPub: kemPk,
      createdAt: now ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'x25519Seed': b64(x25519Seed),
    'x25519Pub': b64(x25519Pub),
    'kemSecret': b64(kemSecret),
    'kemPub': b64(kemPub),
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  /// Strict loader: throws [FormatException] on wrong types or lengths.
  factory PreKeyRecord.fromJson(Map<String, dynamic> j) {
    Uint8List b(String k, int len) {
      final v = j[k];
      if (v is! String || v.length > len * 2) throw FormatException('bad $k');
      final out = unb64(v);
      if (out.length != len) throw FormatException('bad $k length');
      return out;
    }

    final id = j['id'], created = j['createdAt'];
    if (id is! String || id.isEmpty || id.length > 32) {
      throw const FormatException('bad id');
    }
    if (created is! int || created < 0 || created > 8640000000000000) {
      throw const FormatException('bad createdAt');
    }
    return PreKeyRecord(
      id: id,
      x25519Seed: b('x25519Seed', 32),
      x25519Pub: b('x25519Pub', 32),
      kemSecret: b('kemSecret', 2400),
      kemPub: b('kemPub', 1184),
      createdAt: DateTime.fromMillisecondsSinceEpoch(created),
    );
  }

  /// True iff each public key belongs to its private half.
  Future<bool> consistent() async =>
      await KeyChecks.x25519Matches(x25519Seed, x25519Pub) &&
      KeyChecks.mlKem768Matches(kemSecret, kemPub);
}

enum PreKeyKind { signed, oneTime }

/// The public part of a prekey as stored in Firestore.
class PublishedPreKey {
  PublishedPreKey({
    required this.id,
    required this.kind,
    required this.x25519Pub,
    required this.kemPub,
    this.sig,
  });

  final String id;
  final PreKeyKind kind;
  final Uint8List x25519Pub, kemPub;
  final Uint8List? sig; // account-identity signature; signed prekeys only

  Map<String, dynamic> toFirestore() => {
    'kind': kind == PreKeyKind.signed ? 'signed' : 'onetime',
    'x25519Pub': b64(x25519Pub),
    'kemPub': b64(kemPub),
    if (sig != null) 'sig': b64(sig!),
  };

  /// Throws [FormatException] on anything malformed (wrong types or lengths).
  factory PublishedPreKey.fromFirestore(String id, Map<String, dynamic> d) {
    try {
      final kind = switch (d['kind']) {
        'signed' => PreKeyKind.signed,
        'onetime' => PreKeyKind.oneTime,
        _ => throw const FormatException('bad kind'),
      };
      final x = unb64(d['x25519Pub'] as String);
      final k = unb64(d['kemPub'] as String);
      if (x.length != 32 || k.length != 1184) {
        throw const FormatException('bad key length');
      }
      final sig = d['sig'] == null ? null : unb64(d['sig'] as String);
      if (kind == PreKeyKind.signed && (sig == null || sig.length > 8192)) {
        throw const FormatException('missing signature');
      }
      return PublishedPreKey(
        id: id,
        kind: kind,
        x25519Pub: x,
        kemPub: k,
        sig: sig,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('malformed prekey');
    }
  }
}

/// Everything an initiator needs to start a session with one remote device.
class PreKeyBundle {
  PreKeyBundle({required this.device, required this.signed, this.oneTime});
  final DeviceBundle device;
  final PublishedPreKey signed;
  final PublishedPreKey? oneTime;
}

class PreKeys {
  static Uint8List signedMessage(
    String uid,
    String deviceId,
    String id,
    List<int> x25519Pub,
    List<int> kemPub,
  ) => lp([
    utf8Bytes('fireplace/v2/signed-prekey'),
    utf8Bytes(uid),
    utf8Bytes(deviceId),
    utf8Bytes(id),
    x25519Pub,
    kemPub,
  ]);

  /// Signs [r] with the account identity, binding it to this uid and device.
  static Future<PublishedPreKey> sign(
    PreKeyRecord r,
    AccountIdentity identity,
    String uid,
    String deviceId,
  ) async => PublishedPreKey(
    id: r.id,
    kind: PreKeyKind.signed,
    x25519Pub: r.x25519Pub,
    kemPub: r.kemPub,
    sig: await identity.sign(
      signedMessage(uid, deviceId, r.id, r.x25519Pub, r.kemPub),
    ),
  );

  static PublishedPreKey oneTime(PreKeyRecord r) => PublishedPreKey(
    id: r.id,
    kind: PreKeyKind.oneTime,
    x25519Pub: r.x25519Pub,
    kemPub: r.kemPub,
  );

  /// True iff [spk] was signed by [device]'s account identity for that device.
  static Future<bool> verifySigned(
    DeviceBundle device,
    PublishedPreKey spk,
  ) async {
    if (spk.kind != PreKeyKind.signed || spk.sig == null) return false;
    return AccountIdentity.verify(
      device.identityPub,
      signedMessage(
        device.uid,
        device.deviceId,
        spk.id,
        spk.x25519Pub,
        spk.kemPub,
      ),
      spk.sig!,
    );
  }
}

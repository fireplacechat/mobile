part of 'crypto_backend.dart';

class AccountIdentity implements reference.AccountIdentity {
  AccountIdentity._(this.value);
  final reference.AccountIdentity value;
  static Future<AccountIdentity> generate() async => AccountIdentity._(
    useRust
        ? reference.AccountIdentity.fromJson(nativeCrypto.identityGenerate())
        : await reference.AccountIdentity.generate(),
  );
  factory AccountIdentity.fromJson(Map<String, dynamic> json) =>
      AccountIdentity._(reference.AccountIdentity.fromJson(json));
  @override
  Uint8List get edPub => value.edPub;
  @override
  Uint8List get dsaPub => value.dsaPub;
  @override
  Uint8List get publicBytes =>
      useRust ? nativeCrypto.identityPublic(toJson()) : value.publicBytes;
  @override
  Map<String, String> toJson() => value.toJson();
  @override
  Future<Uint8List> sign(List<int> message) async => useRust
      ? nativeCrypto.identitySign(toJson(), message)
      : value.sign(message);
  static Future<bool> verify(
    List<int> publicBytes,
    List<int> message,
    List<int> signature,
  ) async => useRust
      ? nativeCrypto.identityVerify(publicBytes, message, signature)
      : reference.AccountIdentity.verify(publicBytes, message, signature);
  @override
  Future<bool> consistent() async =>
      useRust ? nativeCrypto.identityConsistent(toJson()) : value.consistent();
}

class DeviceBundle extends reference.DeviceBundle {
  DeviceBundle({
    required super.uid,
    required super.deviceId,
    required super.x25519Pub,
    required super.kemPub,
    required super.identityPub,
    required super.cert,
  });
  factory DeviceBundle.wrap(reference.DeviceBundle bundle) => DeviceBundle(
    uid: bundle.uid,
    deviceId: bundle.deviceId,
    x25519Pub: bundle.x25519Pub,
    kemPub: bundle.kemPub,
    identityPub: bundle.identityPub,
    cert: bundle.cert,
  );
  factory DeviceBundle.fromFirestore(
    String uid,
    String deviceId,
    Map<String, dynamic> json,
  ) => DeviceBundle.wrap(
    reference.DeviceBundle.fromFirestore(uid, deviceId, json),
  );
  factory DeviceBundle.fromNative(Map<String, dynamic> json) => DeviceBundle(
    uid: json['uid'] as String,
    deviceId: json['deviceId'] as String,
    x25519Pub: reference.unb64(json['x25519Pub']),
    kemPub: reference.unb64(json['kemPub']),
    identityPub: reference.unb64(json['identityPub']),
    cert: reference.unb64(json['cert']),
  );
  static Uint8List certMessage(
    String uid,
    String deviceId,
    List<int> x,
    List<int> kem,
  ) => reference.DeviceBundle.certMessage(uid, deviceId, x, kem);
  @override
  Future<bool> verifyCert() async => useRust
      ? nativeCrypto.deviceVerify(bundleJson(this))
      : super.verifyCert();
}

class DeviceKeys implements reference.DeviceKeys {
  DeviceKeys._(this.value);
  final reference.DeviceKeys value;
  static Future<DeviceKeys> generate() async => DeviceKeys._(
    useRust
        ? reference.DeviceKeys.fromJson(nativeCrypto.deviceGenerate())
        : await reference.DeviceKeys.generate(),
  );
  factory DeviceKeys.fromJson(Map<String, dynamic> json) =>
      DeviceKeys._(reference.DeviceKeys.fromJson(json));
  @override
  String get deviceId => value.deviceId;
  @override
  Uint8List get x25519Seed => value.x25519Seed;
  @override
  Uint8List get x25519Pub => value.x25519Pub;
  @override
  Uint8List get kemPub => value.kemPub;
  @override
  Uint8List get kemSecret => value.kemSecret;
  @override
  Map<String, String> toJson() => value.toJson();
  @override
  Future<DeviceBundle> certify(
    reference.AccountIdentity identity,
    String uid,
  ) async => useRust
      ? DeviceBundle.fromNative(
          nativeCrypto.deviceCertify(toJson(), identity.toJson(), uid),
        )
      : DeviceBundle.wrap(await value.certify(identity, uid));
  @override
  Future<bool> consistent() async =>
      useRust ? nativeCrypto.deviceConsistent(toJson()) : value.consistent();
}

class PreKeyRecord extends reference.PreKeyRecord {
  PreKeyRecord({
    required super.id,
    required super.x25519Seed,
    required super.x25519Pub,
    required super.kemSecret,
    required super.kemPub,
    required super.createdAt,
  });
  factory PreKeyRecord.wrap(reference.PreKeyRecord value) => PreKeyRecord(
    id: value.id,
    x25519Seed: value.x25519Seed,
    x25519Pub: value.x25519Pub,
    kemSecret: value.kemSecret,
    kemPub: value.kemPub,
    createdAt: value.createdAt,
  );
  factory PreKeyRecord.fromJson(Map<String, dynamic> json) =>
      PreKeyRecord.wrap(reference.PreKeyRecord.fromJson(json));
  static Future<PreKeyRecord> generate({DateTime? now}) async => useRust
      ? PreKeyRecord.fromJson(
          nativeCrypto.prekeyGenerate(
            (now ?? DateTime.now()).millisecondsSinceEpoch,
          ),
        )
      : PreKeyRecord.wrap(await reference.PreKeyRecord.generate(now: now));
  @override
  Future<bool> consistent() async => useRust
      ? nativeCrypto.deviceConsistent({
          'deviceId': 'prekey-check',
          'x25519Seed': reference.b64(x25519Seed),
          'x25519Pub': reference.b64(x25519Pub),
          'kemSecret': reference.b64(kemSecret),
          'kemPub': reference.b64(kemPub),
        })
      : super.consistent();
}

class PreKeys {
  static Future<reference.PublishedPreKey> sign(
    reference.PreKeyRecord record,
    reference.AccountIdentity identity,
    String uid,
    String device,
  ) async => useRust
      ? published(
          nativeCrypto.prekeySign(
            record.toJson(),
            identity.toJson(),
            uid,
            device,
          ),
        )
      : reference.PreKeys.sign(record, identity, uid, device);
  static reference.PublishedPreKey oneTime(reference.PreKeyRecord record) =>
      useRust
      ? published(nativeCrypto.prekeyOneTime(record.toJson()))
      : reference.PreKeys.oneTime(record);
  static Future<bool> verifySigned(
    reference.DeviceBundle bundle,
    reference.PublishedPreKey key,
  ) async => useRust
      ? nativeCrypto.prekeyVerify(bundleJson(bundle), {
          'id': key.id,
          ...key.toFirestore(),
        })
      : reference.PreKeys.verifySigned(bundle, key);
  static Uint8List signedMessage(
    String uid,
    String device,
    String id,
    List<int> x,
    List<int> kem,
  ) => reference.PreKeys.signedMessage(uid, device, id, x, kem);
}

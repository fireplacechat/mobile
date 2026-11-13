part of 'crypto_backend.dart';

class RecoveryKey {
  RecoveryKey._(this.bytes, this._dart);
  final Uint8List bytes;
  final reference.RecoveryKey? _dart;
  static RecoveryKey generate() {
    if (useRust) return RecoveryKey._(nativeCrypto.recoveryGenerate(), null);
    final key = reference.RecoveryKey.generate();
    return RecoveryKey._(key.bytes, key);
  }

  Future<String> display() async =>
      _dart?.display() ?? nativeCrypto.recoveryDisplay(bytes);
  static Future<RecoveryKey?> parse(String text) async {
    if (!useRust) {
      final key = await reference.RecoveryKey.parse(text);
      return key == null ? null : RecoveryKey._(key.bytes, key);
    }
    try {
      return RecoveryKey._(nativeCrypto.recoveryParse(text), null);
    } on NativeCryptoException catch (error) {
      if (error.code == 1) return null;
      rethrow;
    }
  }
}

class RecoveryBackup {
  static Future<String> encrypt(
    reference.AccountIdentity identity,
    RecoveryKey key,
  ) async => useRust
      ? nativeCrypto.recoveryEncrypt(identity.toJson(), key.bytes)
      : reference.RecoveryBackup.encrypt(identity, key._dart!);
  static Future<AccountIdentity> decrypt(String blob, RecoveryKey key) async {
    if (!useRust) {
      return AccountIdentity._(
        await reference.RecoveryBackup.decrypt(blob, key._dart!),
      );
    }
    try {
      return AccountIdentity.fromJson(
        nativeCrypto.recoveryDecrypt(blob, key.bytes),
      );
    } on NativeCryptoException {
      throw reference.BackupException();
    }
  }
}

class LinkCrypto {
  static Future<String> requestFingerprint(List<int> x, List<int> kem) async =>
      useRust
      ? nativeCrypto.linkFingerprint(x, kem)
      : reference.LinkCrypto.requestFingerprint(x, kem);
  static Future<String> confirmationCode(
    List<int> identity,
    List<int> x,
    List<int> kem,
  ) async => useRust
      ? nativeCrypto.linkConfirmation(identity, x, kem)
      : reference.LinkCrypto.confirmationCode(identity, x, kem);
  static Future<reference.SealedIdentity> seal(
    reference.AccountIdentity identity, {
    required String uid,
    required String deviceId,
    required Uint8List x25519Pub,
    required Uint8List kemPub,
  }) async {
    if (!useRust) {
      return reference.LinkCrypto.seal(
        identity,
        uid: uid,
        deviceId: deviceId,
        x25519Pub: x25519Pub,
        kemPub: kemPub,
      );
    }
    try {
      return reference.SealedIdentity.fromJson(
        nativeCrypto.linkSeal(
          identity.toJson(),
          uid,
          deviceId,
          x25519Pub,
          kemPub,
        ),
      );
    } on NativeCryptoException {
      throw reference.LinkException('Invalid device linking key.');
    }
  }

  static Future<AccountIdentity> open(
    reference.SealedIdentity sealed, {
    required String uid,
    required reference.DeviceKeys keys,
  }) async {
    if (!useRust) {
      return AccountIdentity._(
        await reference.LinkCrypto.open(sealed, uid: uid, keys: keys),
      );
    }
    try {
      return AccountIdentity.fromJson(
        nativeCrypto.linkOpen(sealed.toJson(), uid, keys.toJson()),
      );
    } on NativeCryptoException {
      throw reference.LinkException(
        'Could not decrypt the transferred identity.',
      );
    }
  }
}

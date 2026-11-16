part of 'backend.dart';

class RecoveryKey {
  RecoveryKey._(this.bytes, this._dart);
  final Uint8List bytes;
  final reference.RecoveryKey? _dart;
  static RecoveryKey generate() {
    if (useRust) return RecoveryKey._(_nativeCrypto.recoveryGenerate(), null);
    final key = reference.RecoveryKey.generate();
    return RecoveryKey._(key.bytes, key);
  }

  Future<String> display() async =>
      _dart?.display() ?? _nativeCrypto.recoveryDisplay(bytes);

  // A recovery key is portable data, unlike a live session. Tests can move it
  // between backend scopes without changing or regenerating its bytes.
  Future<reference.RecoveryKey> _asDart() async =>
      _dart ??
      (await reference.RecoveryKey.parse(
        _nativeCrypto.recoveryDisplay(bytes),
      ))!;
  static Future<RecoveryKey?> parse(String text) async {
    if (!useRust) {
      final key = await reference.RecoveryKey.parse(text);
      return key == null ? null : RecoveryKey._(key.bytes, key);
    }
    try {
      return RecoveryKey._(_nativeCrypto.recoveryParse(text), null);
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
      ? _nativeCrypto.recoveryEncrypt(identity.toJson(), key.bytes)
      : reference.RecoveryBackup.encrypt(identity, await key._asDart());
  static Future<AccountIdentity> decrypt(String blob, RecoveryKey key) async {
    if (!useRust) {
      return AccountIdentity._(
        await reference.RecoveryBackup.decrypt(blob, await key._asDart()),
      );
    }
    try {
      return AccountIdentity.fromJson(
        _nativeCrypto.recoveryDecrypt(blob, key.bytes),
      );
    } on NativeCryptoException {
      throw reference.BackupException();
    }
  }
}

class LinkCrypto {
  /// The random value a new device shows in its QR code and sends nowhere.
  static Uint8List newSecret() {
    final random = Random.secure();
    return Uint8List.fromList([
      for (var i = 0; i < reference.LinkCrypto.secretLength; i++)
        random.nextInt(256),
    ]);
  }

  static Future<String> requestFingerprint(List<int> x, List<int> kem) async =>
      useRust
      ? _nativeCrypto.linkFingerprint(x, kem)
      : reference.LinkCrypto.requestFingerprint(x, kem);
  static Future<reference.SealedIdentity> seal(
    reference.AccountIdentity identity, {
    required String uid,
    required String deviceId,
    required Uint8List x25519Pub,
    required Uint8List kemPub,
    required List<int> secret,
  }) async {
    if (!useRust) {
      return reference.LinkCrypto.seal(
        identity,
        uid: uid,
        deviceId: deviceId,
        x25519Pub: x25519Pub,
        kemPub: kemPub,
        secret: secret,
      );
    }
    try {
      return reference.SealedIdentity.fromJson(
        _nativeCrypto.linkSeal(
          identity.toJson(),
          uid,
          deviceId,
          x25519Pub,
          kemPub,
          secret,
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
    required List<int> secret,
  }) async {
    if (!useRust) {
      return AccountIdentity._(
        await reference.LinkCrypto.open(
          sealed,
          uid: uid,
          keys: keys,
          secret: secret,
        ),
      );
    }
    try {
      return AccountIdentity.fromJson(
        _nativeCrypto.linkOpen(sealed.toJson(), uid, keys.toJson(), secret),
      );
    } on NativeCryptoException {
      throw reference.LinkException(
        'Could not decrypt the transferred identity.',
      );
    }
  }
}

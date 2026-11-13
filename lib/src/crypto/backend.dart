/// App-facing crypto seam. The original Dart files remain the reference.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:fireplace/src/crypto/dart_reference.dart' as reference;
import 'package:fireplace_native/fireplace_crypto.dart';

export 'package:fireplace/src/crypto/dart_reference.dart'
    hide
        AccountIdentity,
        DeviceKeys,
        DeviceBundle,
        PreKeyRecord,
        PreKeys,
        Session,
        RecoveryKey,
        RecoveryBackup,
        LinkCrypto,
        identityFingerprint,
        safetyNumber;

part 'backend_keys.dart';
part 'backend_session.dart';
part 'backend_recovery.dart';

enum CryptoBackendKind { dart, rust }

class CryptoBackend {
  static final _zoneKey = Object();
  // Switching the production default is a separate, explicitly reviewed change.
  static const production = bool.fromEnvironment('FIREPLACE_RUST_CRYPTO')
      ? CryptoBackendKind.rust
      : CryptoBackendKind.dart;
  static CryptoBackendKind get current =>
      Zone.current[_zoneKey] as CryptoBackendKind? ?? production;
  static T runWith<T>(CryptoBackendKind backend, T Function() body) =>
      runZoned(body, zoneValues: {_zoneKey: backend});
}

bool get useRust => CryptoBackend.current == CryptoBackendKind.rust;
NativeCrypto? _core;
NativeCrypto get _nativeCrypto => _core ??= NativeCrypto(
  Platform.isIOS
      ? DynamicLibrary.process()
      : DynamicLibrary.open(
          Platform.isAndroid
              ? 'libfireplace_crypto.so'
              : File(
                  'build/fireplace_crypto/host/release/${Platform.isWindows ? 'fireplace_crypto.dll' : 'libfireplace_crypto.so'}',
                ).absolute.path,
        ),
);

T _sessionOperation<T>(T Function() operation) {
  try {
    return operation();
  } on NativeCryptoException catch (error) {
    if (error.code == 3) throw reference.SessionRateLimited();
    throw reference.SessionException(
      'Could not process the encrypted message.',
    );
  }
}

Map<String, dynamic> _bundleJson(reference.DeviceBundle bundle) => {
  'uid': bundle.uid,
  'deviceId': bundle.deviceId,
  'x25519Pub': reference.b64(bundle.x25519Pub),
  'kemPub': reference.b64(bundle.kemPub),
  'identityPub': reference.b64(bundle.identityPub),
  'cert': reference.b64(bundle.cert),
};
reference.PublishedPreKey _published(Map<String, dynamic> json) =>
    reference.PublishedPreKey.fromFirestore(json['id'] as String, json);

Future<String> identityFingerprint(List<int> identity) async => useRust
    ? _nativeCrypto.fingerprint(identity)
    : reference.identityFingerprint(identity);
Future<String> safetyNumber(List<int> a, List<int> b) async =>
    useRust ? _nativeCrypto.safetyNumber(a, b) : reference.safetyNumber(a, b);

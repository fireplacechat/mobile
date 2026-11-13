// The reference classes are untouched. This test-only facade runs the same
// protocol assertions through Dart and through the core's C ABI.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:fireplace/fireplace_crypto.dart' as reference;
import 'package:fireplace_native/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

export 'package:fireplace/fireplace_crypto.dart'
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

part 'crypto_backend_keys.dart';
part 'crypto_backend_session.dart';
part 'crypto_backend_recovery.dart';

bool useRust = false;
bool? initiateWithRust;
bool? acceptWithRust;
bool Function()? reloadWithRust;
NativeCrypto? _native;
final _live = <NativeSession>[];

NativeCrypto get nativeCrypto => _native ??= NativeCrypto(
  DynamicLibrary.open(
    const String.fromEnvironment('CRYPTO_TEST_LIBRARY').isNotEmpty
        ? const String.fromEnvironment('CRYPTO_TEST_LIBRARY')
        : File(
            'build/fireplace_crypto/host/release/${Platform.isWindows ? 'fireplace_crypto.dll' : 'libfireplace_crypto.so'}',
          ).absolute.path,
  ),
);

T sessionOperation<T>(T Function() operation) {
  try {
    return operation();
  } on NativeCryptoException catch (error) {
    if (error.code == 3) throw reference.SessionRateLimited();
    throw reference.SessionException('Native session operation refused.');
  }
}

NativeSession track(NativeSession session) {
  _live.add(session);
  return session;
}

void closeNativeSessions() {
  for (final session in _live) {
    session.close();
  }
  _live.clear();
}

void bothCryptoBackends(void Function() define) {
  for (final rust in [false, true]) {
    group(rust ? 'Rust C ABI' : 'Dart reference', () {
      setUpAll(() {
        useRust = rust;
        if (rust && !nativeCrypto.library.providesSymbol('fp_session_load')) {
          throw StateError(
            'The live-session ABI requires fireplace-crypto 0.1.1.',
          );
        }
      });
      tearDown(closeNativeSessions);
      tearDownAll(closeNativeSessions);
      define();
    });
  }
}

Map<String, dynamic> bundleJson(reference.DeviceBundle bundle) => {
  'uid': bundle.uid,
  'deviceId': bundle.deviceId,
  'x25519Pub': reference.b64(bundle.x25519Pub),
  'kemPub': reference.b64(bundle.kemPub),
  'identityPub': reference.b64(bundle.identityPub),
  'cert': reference.b64(bundle.cert),
};

reference.PublishedPreKey published(Map<String, dynamic> json) =>
    reference.PublishedPreKey.fromFirestore(json['id'] as String, json);

Future<String> identityFingerprint(List<int> identity) async => useRust
    ? nativeCrypto.fingerprint(identity)
    : reference.identityFingerprint(identity);
Future<String> safetyNumber(List<int> a, List<int> b) async =>
    useRust ? nativeCrypto.safetyNumber(a, b) : reference.safetyNumber(a, b);

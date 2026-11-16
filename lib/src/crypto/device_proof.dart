import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/crypto/contributory.dart';

/// Shows the server that a request comes from a device of the account, not
/// from a session that only has the password (decision 0063).
///
/// The proof is a MAC over the request, keyed by the shared secret between
/// this device's long-term X25519 key and a key of the server. The server
/// computes the same secret from the device's published key. The secret is
/// used only through HKDF with this label, so the proof says nothing that
/// helps with a message session.
abstract final class DeviceProof {
  static const _label = 'fireplace/v1/device-proof';

  /// What is authenticated: who asks, for what, and under which request id,
  /// so a proof cannot be moved to another request.
  static Uint8List message({
    required String uid,
    required String deviceId,
    required String requestId,
    required String kind,
    required List<String> arguments,
  }) => lp([
    utf8Bytes(_label),
    utf8Bytes(uid),
    utf8Bytes(deviceId),
    utf8Bytes(requestId),
    utf8Bytes(kind),
    for (final a in arguments) utf8Bytes(a),
  ]);

  static Future<Uint8List> make({
    required List<int> deviceSeed,
    required List<int> devicePub,
    required List<int> serverPub,
    required Uint8List message,
  }) async {
    final x = X25519();
    final pair = await x.newKeyPairFromSeed(deviceSeed);
    final shared = await (await x.sharedSecretKey(
      keyPair: pair,
      remotePublicKey: SimplePublicKey(serverPub, type: KeyPairType.x25519),
    )).extractBytes();
    if (!isContributoryX25519Secret(shared)) {
      throw ArgumentError('Invalid server key.');
    }
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(shared),
      nonce: const <int>[],
      info: lp([utf8Bytes(_label), devicePub, serverPub]),
    );
    final mac = await Hmac.sha256().calculateMac(message, secretKey: key);
    return Uint8List.fromList(mac.bytes);
  }
}

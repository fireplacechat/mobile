import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pqcrypto/pqcrypto.dart';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/crypto/key_checks.dart';

/// Account-level hybrid signing identity: Ed25519 + ML-DSA-65.
/// A signature is valid only if BOTH component signatures verify, so forging
/// one requires breaking both the classical and the post-quantum scheme.
class AccountIdentity {
  AccountIdentity._(this._edSeed, this.edPub, this._dsaSecret, this.dsaPub);

  static const _ctx = 'fireplace/v1';
  static final _ed = Ed25519();
  static final _params = DilithiumParams.mlDsa65;

  final Uint8List _edSeed;
  final Uint8List edPub;
  final Uint8List _dsaSecret;
  final Uint8List dsaPub;

  static Future<AccountIdentity> generate() async {
    final seed = randomBytes(32);
    final kp = await _ed.newKeyPairFromSeed(seed);
    final pub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    final (dsaPk, dsaSk) = MlDsa.generateKeyPair(_params);
    return AccountIdentity._(seed, pub, dsaSk, dsaPk);
  }

  /// Public identity bytes, shared with peers and pinned by them.
  Uint8List get publicBytes => lp([edPub, dsaPub]);

  Future<Uint8List> sign(List<int> message) async {
    final kp = await _ed.newKeyPairFromSeed(_edSeed);
    final edSig = (await _ed.sign(message, keyPair: kp)).bytes;
    final dsaSig = MlDsa.sign(
      _dsaSecret,
      Uint8List.fromList(message),
      _params,
      ctx: utf8Bytes(_ctx),
    );
    return lp([edSig, dsaSig]);
  }

  static Future<bool> verify(
    List<int> publicBytes,
    List<int> message,
    List<int> signature,
  ) async {
    try {
      final pub = unlp(publicBytes);
      final sig = unlp(signature);
      if (pub.length != 2 || sig.length != 2) return false;
      final edOk = await _ed.verify(
        message,
        signature: Signature(
          sig[0],
          publicKey: SimplePublicKey(pub[0], type: KeyPairType.ed25519),
        ),
      );
      if (!edOk) return false;
      return MlDsa.verify(
        pub[1],
        Uint8List.fromList(message),
        sig[1],
        _params,
        ctx: utf8Bytes(_ctx),
      );
    } catch (_) {
      return false;
    }
  }

  Map<String, String> toJson() => {
    'edSeed': b64(_edSeed),
    'edPub': b64(edPub),
    'dsaSecret': b64(_dsaSecret),
    'dsaPub': b64(dsaPub),
  };

  /// Strict loader: throws [FormatException] on wrong types or lengths.
  factory AccountIdentity.fromJson(Map<String, dynamic> j) {
    Uint8List b(String k, int len) {
      final v = j[k];
      if (v is! String || v.length > len * 2) throw FormatException('bad $k');
      final out = unb64(v);
      if (out.length != len) throw FormatException('bad $k length');
      return out;
    }

    return AccountIdentity._(
      b('edSeed', 32),
      b('edPub', 32),
      b('dsaSecret', 4032),
      b('dsaPub', 1952),
    );
  }

  /// True iff the Ed25519 public key matches its seed AND a fresh hybrid signature
  /// verifies under the public identity (which proves the ML-DSA halves belong together).
  Future<bool> consistent() async {
    if (!await KeyChecks.x25519LikeEd25519Matches(_edSeed, edPub)) return false;
    final probe = randomBytes(16);
    return verify(publicBytes, probe, await sign(probe));
  }
}

import 'package:cryptography/cryptography.dart';

import 'codec.dart';

/// Consistency checks for key material loaded from storage. A length check only proves
/// a value has the right size; these prove the public and private halves belong together,
/// so a corrupted or half-restored record is rejected instead of silently misbehaving.
class KeyChecks {
  static const x25519Len = 32;
  static const mlKem768SecretLen = 2400;
  static const mlKem768PublicLen = 1184;

  /// True iff [pub] is the X25519 public key of [seed].
  static Future<bool> x25519Matches(List<int> seed, List<int> pub) async {
    if (seed.length != x25519Len || pub.length != x25519Len) return false;
    final kp = await X25519().newKeyPairFromSeed(seed);
    return bytesEqual((await kp.extractPublicKey()).bytes, pub);
  }

  /// True iff [pub] is the Ed25519 public key of [seed].
  static Future<bool> x25519LikeEd25519Matches(
    List<int> seed,
    List<int> pub,
  ) async {
    if (seed.length != 32 || pub.length != 32) return false;
    final kp = await Ed25519().newKeyPairFromSeed(seed);
    return bytesEqual((await kp.extractPublicKey()).bytes, pub);
  }

  /// FIPS 203 decapsulation keys embed the encapsulation key right after the
  /// 1152-byte K-PKE secret (dk = dk_PKE || ek || H(ek) || z). This checks the embedded
  /// copy against the public key we store next to it.
  static bool mlKem768Matches(List<int> secret, List<int> pub) {
    if (secret.length != mlKem768SecretLen || pub.length != mlKem768PublicLen) {
      return false;
    }
    return bytesEqual(secret.sublist(1152, 1152 + mlKem768PublicLen), pub);
  }
}

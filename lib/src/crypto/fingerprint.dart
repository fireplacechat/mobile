import 'package:cryptography/cryptography.dart';

import 'package:fireplace/src/crypto/codec.dart';

/// Short fingerprint of one account identity (hex, grouped).
Future<String> identityFingerprint(List<int> identityPub) async {
  final h = (await Sha256().hash(
    lp([utf8Bytes('fireplace/v1/fp'), identityPub]),
  )).bytes;
  final hex = h.take(15).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return [for (var i = 0; i < hex.length; i += 5) hex.substring(i, i + 5)]
      .join(' ');
}

/// Symmetric 60-digit safety number for a pair of identities: both users see
/// the same value regardless of order. Compare in person or via QR.
Future<String> safetyNumber(List<int> identityA, List<int> identityB) async {
  final sorted = [identityA, identityB]
    ..sort((x, y) {
      for (var i = 0; i < x.length && i < y.length; i++) {
        if (x[i] != y[i]) return x[i] - y[i];
      }
      return x.length - y.length;
    });
  final h = (await Sha512().hash(
    lp([utf8Bytes('fireplace/v1/safety'), ...sorted]),
  )).bytes;
  final groups = <String>[];
  for (var i = 0; i < 60; i += 5) {
    var v = 0;
    for (final b in h.sublist(i, i + 5)) {
      v = (v << 8) | b;
    }
    groups.add((v % 100000).toString().padLeft(5, '0'));
  }
  return groups.join(' ');
}

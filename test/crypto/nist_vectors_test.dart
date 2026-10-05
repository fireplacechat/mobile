@TestOn('vm')
library;

// Known-answer tests: the post-quantum primitives against NIST's official ACVP vectors
// (https://github.com/usnistgov/ACVP-Server, FIPS 203 / FIPS 204), restricted to the
// parameter sets Fireplace uses: ML-KEM-768 and ML-DSA-65. They prove the library computes
// exactly what the standards specify. They do NOT prove that Fireplace's handshake or
// ratchet is secure; that is a separate question (see docs/protocol/threat-model.md).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqcrypto/pqcrypto.dart';

Uint8List h(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return out;
}

String hx(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

Map<String, dynamic> load(String name) =>
    jsonDecode(File('test/vectors/$name').readAsStringSync())
        as Map<String, dynamic>;

List<Map<String, dynamic>> rows(Map<String, dynamic> m, String key) =>
    (m[key] as List).cast<Map<String, dynamic>>();

bool throwsOn(void Function() f) {
  try {
    f();
    return false;
  } catch (_) {
    return true;
  }
}

void main() {
  final kem = load('nist_mlkem768.json');
  final dsa = load('nist_mldsa65.json');
  final kyber = PqcKem.kyber768;
  final params = DilithiumParams.mlDsa65;

  group('ML-KEM-768 (FIPS 203)', () {
    test(
      'key generation from (d, z) matches ${rows(kem, 'keyGen').length} vectors',
      () {
        for (final t in rows(kem, 'keyGen')) {
          final (ek, dk) = kyber.generateKeyPair(
            Uint8List.fromList([...h(t['d']), ...h(t['z'])]),
          );
          expect(hx(ek), t['ek'], reason: 'ek tcId ${t['tcId']}');
          expect(hx(dk), t['dk'], reason: 'dk tcId ${t['tcId']}');
        }
      },
    );

    test(
      'encapsulation with fixed m matches ${rows(kem, 'encaps').length} vectors',
      () {
        for (final t in rows(kem, 'encaps')) {
          final (c, k) = kyber.encapsulate(h(t['ek']), h(t['m']));
          expect(hx(c), t['c'], reason: 'ciphertext tcId ${t['tcId']}');
          expect(hx(k), t['k'], reason: 'secret tcId ${t['tcId']}');
        }
      },
    );

    test(
      'decapsulation matches ${rows(kem, 'decaps').length} vectors (incl. implicit rejection)',
      () {
        for (final t in rows(kem, 'decaps')) {
          expect(
            hx(kyber.decapsulate(h(t['dk']), h(t['c']))),
            t['k'],
            reason: 'tcId ${t['tcId']}',
          );
        }
      },
    );

    test('encapsulation-key validity check agrees with NIST', () {
      for (final t in rows(kem, 'ekCheck')) {
        final rejected = throwsOn(
          () => kyber.encapsulate(h(t['ek']), Uint8List(32)),
        );
        expect(
          rejected,
          !(t['testPassed'] as bool),
          reason: 'tcId ${t['tcId']}',
        );
      }
    });
  });

  group('ML-DSA-65 (FIPS 204)', () {
    test(
      'key generation from seed matches ${rows(dsa, 'keyGen').length} vectors',
      () {
        for (final t in rows(dsa, 'keyGen')) {
          final (pk, sk) = MlDsa.generateKeyPairSeeded(params, h(t['seed']));
          expect(hx(pk), t['pk'], reason: 'pk tcId ${t['tcId']}');
          expect(hx(sk), t['sk'], reason: 'sk tcId ${t['tcId']}');
        }
      },
    );

    test(
      'signing (deterministic and with supplied rnd) matches ${rows(dsa, 'sigGen').length} vectors',
      () {
        for (final t in rows(dsa, 'sigGen')) {
          final sig = MlDsa.sign(
            h(t['sk']),
            h(t['message']),
            params,
            ctx: h(t['context']),
            rnd: t['deterministic'] == true ? Uint8List(32) : h(t['rnd']),
          );
          expect(hx(sig), t['signature'], reason: 'tcId ${t['tcId']}');
        }
      },
    );

    test(
      'verification accepts and rejects exactly as NIST says (${rows(dsa, 'sigVer').length} vectors)',
      () {
        var rejected = 0;
        for (final t in rows(dsa, 'sigVer')) {
          final ok = MlDsa.verify(
            h(t['pk']),
            h(t['message']),
            h(t['signature']),
            params,
            ctx: h(t['context']),
          );
          expect(ok, t['testPassed'], reason: 'tcId ${t['tcId']}');
          if (t['testPassed'] == false) rejected++;
        }
        expect(
          rejected,
          greaterThan(0),
          reason: 'the set must include invalid signatures',
        );
      },
    );
  });
}

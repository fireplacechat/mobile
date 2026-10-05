@TestOn('vm')
library;

// Known-answer and attack-case tests for the classical primitives, using Google's
// Wycheproof vectors (https://github.com/C2SP/wycheproof). The Wycheproof sets deliberately
// include malformed, tampered and edge-case inputs, so they check that bad input is
// REJECTED, not just that good input works. These prove the library, not Fireplace's
// protocol (see docs/protocol/threat-model.md).

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> h(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

String hx(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final v = jsonDecode(
    File('test/vectors/wycheproof_classical.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  List<Map<String, dynamic>> rows(String k) =>
      (v[k] as List).cast<Map<String, dynamic>>();

  test('X25519 shared secrets match (${rows('x25519').length} vectors)', () async {
    final x = X25519();
    var checked = 0;
    var refused = 0;
    for (final t in rows('x25519')) {
      final mine = await x.newKeyPairFromSeed(h(t['private']));
      try {
        final shared = await x.sharedSecretKey(
          keyPair: mine,
          remotePublicKey: SimplePublicKey(
            h(t['public']),
            type: KeyPairType.x25519,
          ),
        );
        // 'acceptable' cases (low-order points etc.) may legitimately differ or be refused;
        // for 'valid' ones the answer must be exactly right.
        if (t['result'] == 'valid') {
          expect(
            hx(await shared.extractBytes()),
            t['shared'],
            reason: 'tcId ${t['tcId']}',
          );
          checked++;
        }
      } catch (_) {
        refused++;
        expect(
          t['result'],
          'acceptable',
          reason: 'valid vector refused, tcId ${t['tcId']}',
        );
      }
    }
    expect(checked, greaterThan(200));
    // ignore: avoid_print
    print(
      'X25519: $checked valid vectors matched, $refused unusual inputs refused',
    );
  });

  test(
    'Ed25519 accepts valid and rejects invalid signatures (${rows('ed25519').length} vectors)',
    () async {
      final ed = Ed25519();
      var invalidSeen = 0;
      for (final t in rows('ed25519')) {
        bool ok;
        try {
          ok = await ed.verify(
            h(t['msg']),
            signature: Signature(
              h(t['sig']),
              publicKey: SimplePublicKey(h(t['pk']), type: KeyPairType.ed25519),
            ),
          );
        } catch (_) {
          ok = false; // malformed input counts as rejection
        }
        expect(ok, t['result'] == 'valid', reason: 'tcId ${t['tcId']}');
        if (t['result'] == 'invalid') invalidSeen++;
      }
      expect(invalidSeen, greaterThan(50));
    },
  );

  test(
    'AES-256-GCM encrypts as specified and refuses every tampered case (${rows('aesgcm').length} vectors)',
    () async {
      final aead = AesGcm.with256bits();
      for (final t in rows('aesgcm')) {
        final key = SecretKey(h(t['key']));
        final box = SecretBox(
          h(t['ct']),
          nonce: h(t['iv']),
          mac: Mac(h(t['tag'])),
        );
        if (t['result'] == 'valid') {
          expect(
            await aead.decrypt(box, secretKey: key, aad: h(t['aad'])),
            h(t['msg']),
            reason: 'decrypt tcId ${t['tcId']}',
          );
          final enc = await aead.encrypt(
            h(t['msg']),
            secretKey: key,
            nonce: h(t['iv']),
            aad: h(t['aad']),
          );
          expect(
            hx(enc.cipherText),
            t['ct'],
            reason: 'ciphertext tcId ${t['tcId']}',
          );
          expect(hx(enc.mac.bytes), t['tag'], reason: 'tag tcId ${t['tcId']}');
        } else {
          await expectLater(
            aead.decrypt(box, secretKey: key, aad: h(t['aad'])),
            throwsA(isA<Object>()),
            reason: 'invalid case was accepted, tcId ${t['tcId']}',
          );
        }
      }
    },
  );

  test('HKDF-SHA256 output matches (${rows('hkdf').length} vectors)', () async {
    for (final t in rows('hkdf')) {
      if (t['result'] != 'valid') continue;
      final out =
          await Hkdf(
            hmac: Hmac.sha256(),
            outputLength: t['size'] as int,
          ).deriveKey(
            secretKey: SecretKey(h(t['ikm'])),
            nonce: h(t['salt']),
            info: h(t['info']),
          );
      expect(
        hx(await out.extractBytes()),
        t['okm'],
        reason: 'tcId ${t['tcId']}',
      );
    }
  });
}

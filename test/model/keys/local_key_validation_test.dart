import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final backend in CryptoBackendKind.values) {
    for (final corruption in [
      'json',
      'type',
      'identity',
      'device',
      'certificate',
    ]) {
      test(
        '${backend.name}: $corruption corruption still requires recovery and preserves records',
        () => CryptoBackend.runWith(backend, () async {
          final db = FakeFirebaseFirestore();
          final store = MemorySecretStore();
          final original = await KeyService(db, store).ensureDevice('alice');
          switch (corruption) {
            case 'json':
              await store.write('identity:alice', '{');
            case 'type':
              await store.write('device:alice', '[]');
            case 'identity':
              final identity = original.identity.toJson();
              identity['edPub'] = b64((await AccountIdentity.generate()).edPub);
              await store.write('identity:alice', jsonEncode(identity));
            case 'device':
              final device = original.keys.toJson();
              device['x25519Pub'] = b64(
                (await DeviceKeys.generate()).x25519Pub,
              );
              await store.write('device:alice', jsonEncode(device));
            case 'certificate':
              final bundle = original.bundle.toFirestore();
              final cert = unb64(bundle['deviceCert']!);
              cert[cert.length - 1] ^= 1;
              bundle['deviceCert'] = b64(cert);
              await store.write('bundle:alice', jsonEncode(bundle));
          }
          final localBefore = Map.of(store.data);
          final remoteBefore = db.dump();
          await expectLater(
            KeyService(db, store).ensureDevice('alice'),
            throwsA(isA<NeedsRecoveryException>()),
          );
          expect(store.data.keys, unorderedEquals(localBefore.keys));
          for (final entry in localBefore.entries) {
            expect(store.data[entry.key] == entry.value, isTrue);
          }
          expect(db.dump() == remoteBefore, isTrue);
        }),
      );
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:fireplace/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/prekey_helpers.dart';

/// Writes the exact documents the app produces so the Node rules tests
/// (firebase/tests/app_docs.test.js) can replay them against firestore.rules.
void main() {
  // Rewrites firebase/tests/fixtures/app_docs.json with fresh keys. Normal test
  // runs must not dirty the working tree, so this only runs on request:
  //   REGEN_RULES_FIXTURE=1 flutter test test/rules_fixture_test.dart
  final regenerate = Platform.environment['REGEN_RULES_FIXTURE'] == '1';
  test(
    'export app document shapes for the rules tests',
    skip: regenerate ? false : 'set REGEN_RULES_FIXTURE=1 to regenerate',
    () async {
      final id = await AccountIdentity.generate();
      final bId = await AccountIdentity.generate();
      final aKeys = await DeviceKeys.generate();
      final bKeys = await DeviceKeys.generate();
      final a = await aKeys.certify(id, 'alice');
      final b = await bKeys.certify(bId, 'bob');
      final pk = await preKeyed(b, bId);
      final (s, _) = await Session.initiate(
        local: aKeys,
        localBundle: a,
        remote: await pk.claim(),
      );
      final env = await s.encrypt(utf8.encode('x'), chatId: 'alice_bob');

      final device = a.toFirestore();
      expect(device.keys.toSet(), {
        'x25519Pub',
        'kemPub',
        'sigPub',
        'deviceCert',
      });
      final signed = await PreKeys.sign(pk.spk, bId, 'bob', b.deviceId);
      final fixture = {
        'deviceId': a.deviceId,
        'deviceDoc': device,
        'envelope': env.toJson(),
        'signedPreKeyId': signed.id,
        'signedPreKeyDoc': signed.toFirestore(),
        'oneTimePreKeyId': pk.opk!.id,
        'oneTimePreKeyDoc': PreKeys.oneTime(pk.opk!).toFirestore(),
      };
      File(
        'firebase/tests/fixtures/app_docs.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(fixture));
    },
  );
}

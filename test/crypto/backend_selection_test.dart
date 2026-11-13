import 'dart:convert';

import 'package:fireplace/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the production default stays Dart pending explicit review', () {
    expect(CryptoBackend.production, CryptoBackendKind.dart);
    expect(CryptoBackend.current, CryptoBackendKind.dart);
  });

  test(
    'backend overrides cross asynchronous boundaries and restore the caller',
    () async {
      await CryptoBackend.runWith(CryptoBackendKind.rust, () async {
        await Future<void>.value();
        expect(CryptoBackend.current, CryptoBackendKind.rust);
        await CryptoBackend.runWith(CryptoBackendKind.dart, () async {
          await Future<void>.value();
          expect(CryptoBackend.current, CryptoBackendKind.dart);
        });
        expect(CryptoBackend.current, CryptoBackendKind.rust);
      });
      expect(CryptoBackend.current, CryptoBackendKind.dart);
    },
  );

  for (final kind in CryptoBackendKind.values) {
    test(
      '${kind.name}: recovery keys survive a backend scope change',
      () async {
        final (identity, key) = await CryptoBackend.runWith(
          kind,
          () async =>
              (await AccountIdentity.generate(), RecoveryKey.generate()),
        );
        for (final other in CryptoBackendKind.values) {
          await CryptoBackend.runWith(other, () async {
            final backup = await RecoveryBackup.encrypt(identity, key);
            for (final reader in CryptoBackendKind.values) {
              await CryptoBackend.runWith(reader, () async {
                final restored = await RecoveryBackup.decrypt(backup, key);
                expect(restored.toJson(), identity.toJson());
              });
            }
          });
        }
      },
    );

    test(
      '${kind.name}: the public app API keeps existing session JSON and errors',
      () => CryptoBackend.runWith(kind, () async {
        final alice = await AccountIdentity.generate();
        final aliceKeys = await DeviceKeys.generate();
        final aliceBundle = await aliceKeys.certify(alice, 'alice');
        final bob = await AccountIdentity.generate();
        final bobKeys = await DeviceKeys.generate();
        final bobBundle = await bobKeys.certify(bob, 'bob');
        final prekey = await PreKeyRecord.generate();
        final signed = await PreKeys.sign(prekey, bob, 'bob', bobKeys.deviceId);
        final (a, handshake) = await Session.initiate(
          local: aliceKeys,
          localBundle: aliceBundle,
          remote: PreKeyBundle(device: bobBundle, signed: signed),
        );
        addTearDown(a.close);
        final b = await Session.accept(
          local: bobKeys,
          localBundle: bobBundle,
          remote: aliceBundle,
          handshake: handshake,
          signedPreKey: prekey,
        );
        addTearDown(b.close);
        final wire = await a.encrypt(
          utf8.encode('public API probe'),
          chatId: 'c',
        );
        final stored =
            jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>;
        final restored = Session.fromJson(stored);
        addTearDown(restored.close);
        expect(
          utf8.decode(await restored.decrypt(wire, chatId: 'c')),
          'public API probe',
        );
        expect(restored.sessionId, a.sessionId);
        expect(restored.acknowledged, isTrue);
        expect(restored.canSend, isTrue);
        expect(restored.localUid, 'bob');
        expect(restored.remoteUid, 'alice');
        expect(restored.localDevice, bobKeys.deviceId);
        expect(restored.remoteDevice, aliceKeys.deviceId);
        expect(restored.isInitiator, isFalse);
        expect(await restored.selfCheck(), isTrue);
        expect(restored.toJson().keys.toSet(), {
          'pv',
          'localUid',
          'localDevice',
          'remoteUid',
          'remoteDevice',
          'isInitiator',
          'sid',
          'createdAt',
          'st',
        });
        expect(() => Session.fromJson({}), throwsFormatException);
        expect(Session.tryFromJson({}), isNull);
        await expectLater(
          restored.decrypt(wire, chatId: 'c'),
          throwsA(isA<SessionException>()),
        );
      }),
    );
  }
}

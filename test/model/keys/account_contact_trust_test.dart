import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a new account must not inherit verification of another safety number', () async {
    final db = FakeFirebaseFirestore();
    final sharedInstallation = MemorySecretStore();
    final fredKeys = KeyService(db, sharedInstallation);
    final fred = await fredKeys.ensureDevice('fred');
    final peerKeys = KeyService(db, MemorySecretStore());
    final bob = await peerKeys.ensureDevice('bob');
    await fredKeys.fetchDevices('bob');
    await fredKeys.markVerified('bob', bob.identity.publicBytes);
    expect(await fredKeys.isVerified('bob'), isTrue);
    // Sign-out leaves platform secure storage intact, as it does in production.
    final katyKeys = KeyService(db, sharedInstallation);
    final katy = await katyKeys.ensureDevice('katy');
    await katyKeys.fetchDevices('bob');
    expect(
      await safetyNumber(fred.identity.publicBytes, bob.identity.publicBytes),
      isNot(
        await safetyNumber(katy.identity.publicBytes, bob.identity.publicBytes),
      ),
    );
    expect(await katyKeys.isVerified('bob'), isFalse);
    expect(await fredKeys.isVerified('bob'), isTrue);
  });

  test('legacy verification is not adopted into an account', () async {
    final db = FakeFirebaseFirestore();
    final secrets = MemorySecretStore();
    final peer = await KeyService(db, MemorySecretStore()).ensureDevice('bob');
    await secrets.write('pin:bob', b64(peer.identity.publicBytes));
    await secrets.write('verified:bob', b64(peer.identity.publicBytes));
    final keys = KeyService(db, secrets);
    await keys.ensureDevice('fred');
    await keys.fetchDevices('bob');
    expect(await keys.isVerified('bob'), isFalse);
  });

  test(
    'verification survives reopen but requires the same local identity',
    () async {
      final db = FakeFirebaseFirestore();
      final secrets = MemorySecretStore();
      final keys = KeyService(db, secrets);
      await keys.ensureDevice('fred');
      final bob = await KeyService(db, MemorySecretStore()).ensureDevice('bob');
      await keys.fetchDevices('bob');
      await keys.markVerified('bob', bob.identity.publicBytes);
      final reopened = KeyService(db, secrets);
      await reopened.ensureDevice('fred');
      expect(await reopened.isVerified('bob'), isTrue);
      final replaced = KeyService(db, secrets);
      await replaced.installDevice(
        'fred',
        await AccountIdentity.generate(),
        await DeviceKeys.generate(),
      );
      expect(await replaced.isVerified('bob'), isFalse);
      await replaced.clearVerified('bob');
      expect(await replaced.isVerified('bob'), isFalse);
      expect(await reopened.isVerified('bob'), isFalse);
    },
  );
  test('pins and known devices belong to their local account', () async {
    final db = FakeFirebaseFirestore();
    final secrets = MemorySecretStore();
    final fred = KeyService(db, secrets);
    await fred.ensureDevice('fred');
    final bob = await KeyService(db, MemorySecretStore()).ensureDevice('bob');
    expect(await fred.detectNewDevices('bob'), isEmpty);
    await KeyService(
      db,
      MemorySecretStore(),
    ).installDevice('bob', bob.identity, await DeviceKeys.generate());
    final katy = KeyService(db, secrets);
    await katy.ensureDevice('katy');
    expect(await katy.pinnedIdentity('bob'), isNull);
    expect(await katy.detectNewDevices('bob'), isEmpty);
    expect(await fred.detectNewDevices('bob'), hasLength(1));
    await expectLater(fred.ensureDevice('katy'), throwsStateError);
  });
}

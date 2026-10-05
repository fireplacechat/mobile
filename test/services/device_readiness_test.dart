import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

class InterruptedInstallStore extends MemorySecretStore {
  bool interrupt = true;
  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    if (interrupt && key.startsWith('bundle:')) {
      interrupt = false;
      throw StateError(
        'interrupted after the final local write, before publication',
      );
    }
  }
}

void main() {
  test('retry after interrupted publication must not return an unpublished ready device', () async {
    final db = FakeFirebaseFirestore();
    final secrets = InterruptedInstallStore();
    final keys = KeyService(db, secrets);
    await expectLater(keys.ensureDevice('fred'), throwsA(isA<StateError>()));
    // Every local key exists; the first attempt never published a device.
    expect((await db.collection('users/fred/devices').get()).docs, isEmpty);
    LocalDevice? ready;
    try {
      ready = await keys.ensureDevice('fred');
    } on NeedsRecoveryException {
      return; // An explicit recoverable failure is safe; false readiness is not.
    } on DeviceRevokedException {
      return;
    }
    expect(
      (await db.doc('users/fred/devices/${ready.keys.deviceId}').get()).exists,
      isTrue,
    );
  });

  test(
    'missing published device requires recovery without republishing',
    () async {
      final db = FakeFirebaseFirestore();
      final secrets = MemorySecretStore();
      final keys = KeyService(db, secrets);
      final device = await keys.ensureDevice('fred');
      await db.doc('users/fred/devices/${device.keys.deviceId}').delete();
      await expectLater(
        KeyService(db, secrets).ensureDevice('fred'),
        throwsA(isA<NeedsRecoveryException>()),
      );
      expect((await db.collection('users/fred/devices').get()).docs, isEmpty);
    },
  );

  test('partial bundle storage is not overwritten', () async {
    final db = FakeFirebaseFirestore();
    final secrets = MemorySecretStore();
    await secrets.write('bundle:fred', 'incomplete');
    await expectLater(
      KeyService(db, secrets).ensureDevice('fred'),
      throwsStateError,
    );
    expect(await secrets.read('bundle:fred'), 'incomplete');
    expect((await db.collection('users/fred/devices').get()).docs, isEmpty);
  });
  test('published registration matches the persisted bundle', () async {
    final db = FakeFirebaseFirestore();
    final secrets = MemorySecretStore();
    final keys = KeyService(db, secrets);
    final device = await keys.ensureDevice('fred');
    final stored = await secrets.read('device:fred');
    await db.doc('users/fred/devices/${device.keys.deviceId}').set({});
    await expectLater(
      KeyService(db, secrets).ensureDevice('fred'),
      throwsA(isA<NeedsRecoveryException>()),
    );
    expect(await secrets.read('device:fred'), stored);
  });
}

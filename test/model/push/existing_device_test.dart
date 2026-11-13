import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/fireplace_services.dart';

// The background push handler loads this device's keys but never creates a
// device (decision 0030).
void main() {
  test('no keys yet: nothing is created or published', () async {
    final db = FakeFirebaseFirestore();
    final secrets = MemorySecretStore();
    expect(await KeyService(db, secrets).existingDevice('alice'), isNull);
    expect(secrets.data, isEmpty);
    expect((await db.collection('users/alice/devices').get()).docs, isEmpty);
  });

  test('a set-up device is loaded as the app loads it', () async {
    final db = FakeFirebaseFirestore();
    final secrets = MemorySecretStore();
    final made = await KeyService(db, secrets).ensureDevice('alice');
    final loaded = await KeyService(db, secrets).existingDevice('alice');
    expect(loaded?.keys.deviceId, made.keys.deviceId);
  });
}

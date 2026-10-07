import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'timed-out linking deletes only its own request and installs no keys',
    () async {
      final db = FakeFirebaseFirestore();
      final secrets = MemorySecretStore();
      final service = RecoveryService(db, secrets, KeyService(db, secrets));
      final request = await service.startLink('alice');
      final other = await service.startLink('alice');
      await expectLater(
        service.awaitResponse(request, timeout: Duration.zero),
        throwsA(isA<RecoveryException>()),
      );
      final requests = db.collection('users/alice/linkRequests');
      expect((await requests.doc(request.keys.deviceId).get()).exists, isFalse);
      expect((await requests.doc(other.keys.deviceId).get()).exists, isTrue);
      expect(await secrets.read('identity:alice'), isNull);
      expect((await db.collection('users/alice/devices').get()).docs, isEmpty);
      await service.cancelLink(other);
    },
  );
}

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/services/message_limits.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/durability_test.dart' show Phone, eventually;

void main() {
  late FakeFirebaseFirestore db;
  late Phone alice, bob;
  const id = 'alice_bob';
  setUp(() async {
    db = FakeFirebaseFirestore();
    for (final uid in ['alice', 'bob']) {
      await db.collection('users').doc(uid).set({'username': uid});
      await db.collection('usernames').doc(uid).set({'uid': uid});
    }
    alice = await Phone.create(db, 'alice');
    bob = await Phone.create(db, 'bob');
    await alice.chat.startChat('bob');
    await bob.chat.acceptRequest(id);
  });
  tearDown(() async {
    await alice.sub?.cancel();
    await bob.sub?.cancel();
  });
  test(
    'exact cap, emoji and combining characters round-trip unchanged',
    () async {
      bob.sub = bob.chat.startSync(id);
      final bodies = [
        'x' * maxMessageCharacters,
        '🙂' * maxMessageCharacters,
        '\u0001' * maxMessageCharacters,
        '${'x' * (maxMessageCharacters - 2)}e\u0301',
      ];
      for (final body in bodies) {
        await alice.chat.sendText(id, body);
      }
      await eventually(
        () async => (await bob.bodies(id)).length == bodies.length,
        'bounded messages arrive',
      );
      expect(await bob.bodies(id), unorderedEquals(bodies));
      expect(await alice.bodies(id), unorderedEquals(bodies));
    },
  );
  test(
    'one over fails clearly before any history, journal or server mutation',
    () async {
      final secrets = Map<String, String>.of(alice.secrets.data);
      for (final body in [
        'x' * (maxMessageCharacters + 1),
        '🙂' * (maxMessageCharacters + 1),
        '${'x' * (maxMessageCharacters - 1)}e\u0301',
      ]) {
        await expectLater(
          alice.chat.sendText(id, body),
          throwsA(
            isA<ChatException>().having(
              (e) => e.message,
              'clear limit error',
              messageLimitError,
            ),
          ),
        );
      }
      expect(alice.secrets.data, secrets);
      expect(await alice.bodies(id), isEmpty);
      expect((await db.collection('chats/$id/messages').get()).docs, isEmpty);
    },
  );
}

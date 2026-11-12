import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/model/common/daily_counter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../keys/prekey_test.dart' show Phone;

FirebaseException refused() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

/// Refuses every transaction, as the rules do once the day's claims are used.
class _NoClaims extends FakeFirebaseFirestore {
  int transactions = 0;
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactions++;
    throw refused();
  }
}

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  Future<Map<String, dynamic>?> stored(String name) async =>
      (await db.doc('users/alice/limits/$name').get()).data();

  Future<void> act(DailyCounter counter, {bool Function()? refuse}) =>
      counter.withCount((add) {
        final batch = db.batch();
        add(CounterWrite.batch(batch));
        if (refuse?.call() ?? false) return Future.error(refused());
        return batch.commit();
      });

  test('the first action opens a day; the next ones count in it', () async {
    final counter = DailyCounter(db, 'alice', 'chats');
    await act(counter);
    expect((await stored('chats'))!.keys.toSet(), {'at', 'day', 'today'});
    expect((await stored('chats'))!['today'], 1);
    await act(counter);
    await act(counter);
    expect((await stored('chats'))!['today'], 3);
  });

  test('a refused guess is tried in the other form', () async {
    final counter = DailyCounter(db, 'alice', 'chats');
    // Another app session opened the day: opening one again is refused.
    await db.doc('users/alice/limits/chats').set({
      'at': Timestamp.now(),
      'day': Timestamp.now(),
      'today': 7,
    });
    var calls = 0;
    await act(counter, refuse: () => ++calls == 1);
    expect(calls, 2);
    expect((await stored('chats'))!['today'], 8);
  });

  test('refused in every form, the refusal is passed on', () async {
    final counter = DailyCounter(db, 'alice', 'chats');
    var calls = 0;
    await expectLater(
      act(counter, refuse: () => ++calls > 0),
      throwsA(isA<FirebaseException>()),
    );
    expect(calls, 2, reason: 'both forms, and no attempt without a counter');
  });

  test('the action is never tried without its counter', () async {
    // The rules refuse an action without its counter (backend #21).
    final counter = DailyCounter(db, 'alice', 'chats');
    var calls = 0;
    await expectLater(
      act(counter, refuse: () => ++calls <= 2),
      throwsA(isA<FirebaseException>()),
    );
    expect(calls, 2);
    expect(await stored('chats'), isNull, reason: 'nothing counted');
  });

  test('a failure that is not a refusal is not retried', () async {
    final counter = DailyCounter(db, 'alice', 'chats');
    var calls = 0;
    await expectLater(
      counter.withCount((add) {
        calls++;
        return Future<void>.error(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        );
      }),
      throwsA(isA<FirebaseException>()),
    );
    expect(calls, 1);
  });

  test('starting a chat counts it', () async {
    for (final u in ['alice', 'bob', 'carol']) {
      await db.doc('usernames/$u').set({'uid': u});
      await db.doc('users/$u').set({'username': u});
    }
    final alice = await Phone.create(db, 'alice');
    await alice.chat.startChat('bob');
    await alice.chat.startChat('carol');
    await alice.chat.startChat('bob'); // exists already: not counted
    expect((await stored('chats'))!['today'], 2);
  });

  test('claiming a one-time prekey counts it', () async {
    for (final u in ['alice', 'bob']) {
      await db.doc('usernames/$u').set({'uid': u});
      await db.doc('users/$u').set({'username': u});
    }
    final alice = await Phone.create(db, 'alice');
    final bob = await Phone.create(db, 'bob');
    final target = (await alice.keys.fetchDevices('bob')).single;
    final bundle = await alice.prekeys.fetchBundle(target, claimer: 'alice');
    expect(bundle.oneTime, isNotNull);
    expect((await stored('claims'))!['today'], 1);
    expect(bob.uid, 'bob');
  });

  test(
    'once the day\'s claims are used up, the signed prekey alone is used',
    () async {
      final refusing = _NoClaims();
      for (final u in ['alice', 'bob']) {
        await refusing.doc('usernames/$u').set({'uid': u});
        await refusing.doc('users/$u').set({'username': u});
      }
      final alice = await Phone.create(refusing, 'alice');
      await Phone.create(refusing, 'bob');
      final target = (await alice.keys.fetchDevices('bob')).single;
      final bundle = await alice.prekeys.fetchBundle(target, claimer: 'alice');
      expect(bundle.oneTime, isNull);
      expect(bundle.signed, isNotNull);
      expect(refusing.transactions, 2, reason: 'both forms, then it stops');
    },
  );
}

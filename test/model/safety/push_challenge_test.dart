import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/model/safety/push_challenge.dart';
import 'package:flutter_test/flutter_test.dart';

final _token = 'ab' * 32;
final _older = 'cd' * 32;

void main() {
  late FakeFirebaseFirestore db;
  late PushChallenge responder;

  setUp(() async {
    db = FakeFirebaseFirestore();
    responder = PushChallenge(db);
    await db.collection('users').doc('alice').set({'username': 'alice'});
    await db
        .collection('users')
        .doc('alice')
        .collection('blocks')
        .doc('bob')
        .set({'createdAt': 1});
  });

  Future<Map<String, dynamic>?> proof() async =>
      (await db
              .collection('users')
              .doc('alice')
              .collection('challengeProof')
              .doc('current')
              .get())
          .data();

  test('answers a valid challenge and writes nothing else', () async {
    expect(
      await responder.answer({
        'type': 'rateLimitChallenge',
        'challenge': _token,
        'extra': 'ignored',
      }, 'alice'),
      isTrue,
    );
    expect(await proof(), {'token': _token});
    expect((await db.collection('users').doc('alice').get()).data(), {
      'username': 'alice',
    });
    final proofs = await db
        .collection('users')
        .doc('alice')
        .collection('challengeProof')
        .get();
    expect(proofs.docs.map((d) => d.id), ['current']);
    final blocks = await db
        .collection('users')
        .doc('alice')
        .collection('blocks')
        .get();
    expect(blocks.docs.single.id, 'bob');
    expect((await db.collection('users').get()).docs.map((d) => d.id), [
      'alice',
    ]);
  });

  test('replaces an older proof', () async {
    await db
        .collection('users')
        .doc('alice')
        .collection('challengeProof')
        .doc('current')
        .set({'token': _older, 'extra': true});
    expect(
      await responder.answer({
        'type': 'rateLimitChallenge',
        'challenge': _token,
      }, 'alice'),
      isTrue,
    );
    expect(await proof(), {'token': _token});
  });

  test('ignores a push that is not a well-formed challenge', () async {
    final ignored = <Map<String, String>>[
      {'type': 'other', 'challenge': _token},
      {'type': 'rateLimitChallenge', 'challenge': 'ab' * 31},
      {'type': 'rateLimitChallenge', 'challenge': 'a' * 63},
      {'type': 'rateLimitChallenge', 'challenge': '${_token}a'},
      {'type': 'rateLimitChallenge', 'challenge': 'g' * 64},
      {'type': 'rateLimitChallenge', 'challenge': 'AB' * 32},
      {'type': 'rateLimitChallenge'},
      {'challenge': _token},
      <String, String>{},
    ];
    for (final data in ignored) {
      expect(await responder.answer(data, 'alice'), isFalse, reason: '$data');
    }
    expect(
      await responder.answer({
        'type': 'rateLimitChallenge',
        'challenge': _token,
      }, ''),
      isFalse,
    );
    expect(await proof(), isNull);
    expect((await db.collection('users').doc('alice').get()).data(), {
      'username': 'alice',
    });
    expect((await db.collection('users').get()).docs.map((d) => d.id), [
      'alice',
    ]);
  });

  test('a failing write is not thrown', () async {
    final failing = PushChallenge.writing((uid, token) async {
      throw StateError('offline');
    });
    expect(
      await failing.answer({
        'type': 'rateLimitChallenge',
        'challenge': _token,
      }, 'alice'),
      isFalse,
    );
    expect(await proof(), isNull);
  });
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/src/model/account/auth_service.dart';
import 'package:fireplace/src/model/invites/invite_rows.dart';
import 'package:fireplace/src/model/invites/invite_service.dart';
import 'package:flutter_test/flutter_test.dart';

final created = DateTime.utc(2026, 11, 1);

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  await db.doc('users/alice').set({
    'username': 'alice',
    'createdAt': Timestamp.fromDate(created),
  });
  return db;
}

/// Waits for the next state that satisfies [test].
Future<InviteState> next(
  Stream<InviteState> s,
  bool Function(InviteState) test,
) => s.firstWhere(test).timeout(const Duration(seconds: 5));

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  Future<String> getIdToken([bool forceRefresh = false]) async => 'token';
}

class _Credential extends Fake implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
}

class _Auth extends Fake implements FirebaseAuth {
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async => _Credential(_User(email.split('@').first));
}

void main() {
  test('without operator documents the default schedule applies', () async {
    final db = await seeded();
    final s = await next(InviteService(db).watch('alice'), (_) => true);
    expect(s.createdAt.toUtc(), created);
    expect(s.unlockAfter, defaultInviteUnlocks);
    expect(s.paused, isFalse);
    expect(s.slots, isEmpty);
  });

  test('the page follows the operator schedule and allowance live', () async {
    final db = await seeded();
    final states = InviteService(db).watch('alice').asBroadcastStream();
    await next(states, (_) => true);

    unawaited(
      db.doc('config/invites').set({
        'unlockAfter': [0, 0, 0, 0],
      }),
    );
    expect(
      (await next(states, (s) => s.unlockAfter.length == 4)).paused,
      isFalse,
    );

    unawaited(
      db.doc('inviteAllowances/alice').set({
        'unlockAfter': [0, 3600],
      }),
    );
    final own = await next(states, (s) => s.unlockAfter.length == 2);
    expect(own.unlockAfter[1], const Duration(hours: 1));

    // A global pause wins over the account's own allowance.
    unawaited(
      db.doc('config/invites').set({
        'unlockAfter': [0],
        'paused': true,
      }),
    );
    final paused = await next(states, (s) => s.paused);
    expect(paused.unlockAfter, hasLength(2));
  });

  test('creating writes the row and its invite under the code hash', () async {
    final db = await seeded();
    await InviteService(db).create('alice', 1);
    final row = (await db.doc('users/alice/inviteSlots/1').get()).data()!;
    final code = row['code'] as String;
    expect(code, matches(RegExp(r'^[A-Z2-7]{16}$')));
    expect(row['invite'], await AuthService.inviteHash(code));
    expect(row.keys.toSet(), {'code', 'invite', 'at'});
    final invite = (await db.doc('invites/${row['invite']}').get()).data()!;
    expect(invite['by'], 'alice');
    expect(invite['slot'], 1);
    expect(invite.keys.toSet(), {'by', 'slot', 'createdAt'});

    final s = await next(
      InviteService(db).watch('alice'),
      (s) => s.slots.isNotEmpty,
    );
    expect(s.slots[1]!.code, code);
    expect(s.slots[1]!.used, isFalse);
  });

  test(
    'replacing deletes the old invite and points the row at a new one',
    () async {
      final db = await seeded();
      final service = InviteService(db);
      await service.create('alice', 0);
      final before = await next(
        service.watch('alice'),
        (s) => s.slots.isNotEmpty,
      );
      final old = before.slots[0]!;
      await service.replace('alice', 0, old);
      expect((await db.doc('invites/${old.invite}').get()).exists, isFalse);
      final row = (await db.doc('users/alice/inviteSlots/0').get()).data()!;
      expect(row['code'], isNot(old.code));
      expect(row.containsKey('replacedAt'), isTrue);
      expect((await db.doc('invites/${row['invite']}').get()).exists, isTrue);
    },
  );

  test('a sign-up with a person\'s code marks their row used', () async {
    final db = await seeded();
    await InviteService(db).create('alice', 0);
    final code =
        (await db.doc('users/alice/inviteSlots/0').get()).data()!['code']
            as String;
    await AuthService(_Auth(), db).signUp(
      username: 'dan',
      password: 'correct horse',
      inviteCode: formatInviteCode(code),
    );
    final row = (await db.doc('users/alice/inviteSlots/0').get()).data()!;
    expect(row['used'], isTrue);
    // The row says only that it was used, never by whom.
    expect(row.keys.toSet(), {'code', 'invite', 'at', 'used'});
  });

  test('a sign-up with an operator code touches no row', () async {
    final db = await seeded();
    const code = 'ABCDEFGHIJKLMNOP';
    await db.doc('invites/${await AuthService.inviteHash(code)}').set({
      'note': 'ops',
    });
    await AuthService(
      _Auth(),
      db,
    ).signUp(username: 'dan', password: 'correct horse', inviteCode: code);
    expect((await db.doc('users/dan').get()).exists, isTrue);
    expect((await db.collectionGroup('inviteSlots').get()).docs, isEmpty);
  });
}

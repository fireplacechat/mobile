// Nothing private stays on the public profile (decision 0055): the app
// removes the invite hash after sign-up and a "last active" stamp left by an
// older version, and no longer writes one.
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/model/account/profile_privacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'both fields are removed in one write, and nothing else changes',
    () async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('users').doc('alice');
      await ref.set({
        'username': 'alice',
        'displayName': 'Alice',
        'color': 'plum',
        'invite': 'a' * 64,
        'lastActiveAt': DateTime.utc(2026, 11, 1),
      });
      final profile = (await ref.get()).data();
      expect(await removePrivateProfileFields(db, 'alice', profile), isTrue);
      expect((await ref.get()).data(), {
        'username': 'alice',
        'displayName': 'Alice',
        'color': 'plum',
      });
    },
  );

  test('a profile with only one of them, and one already clean', () async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('users').doc('bob');
    await ref.set({'username': 'bob', 'invite': 'b' * 64});
    expect(
      await removePrivateProfileFields(db, 'bob', (await ref.get()).data()),
      isTrue,
    );
    expect((await ref.get()).data(), {'username': 'bob'});
    // Nothing to remove: no write is made.
    expect(
      await removePrivateProfileFields(db, 'bob', (await ref.get()).data()),
      isFalse,
    );
    expect(await removePrivateProfileFields(db, 'bob', null), isFalse);
  });

  test('a failed write is not an error', () async {
    final db = FakeFirebaseFirestore();
    // No such document: the update fails.
    expect(
      await removePrivateProfileFields(db, 'ghost', {'invite': 'c' * 64}),
      isFalse,
    );
  });

  test('the app no longer writes a "last active" stamp anywhere', () {
    final writers = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.endsWith('profile_privacy.dart') &&
            f.readAsStringSync().contains('lastActiveAt'))
          f.path,
    ];
    expect(writers, isEmpty);
  });
}

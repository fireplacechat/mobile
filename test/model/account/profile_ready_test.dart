import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/src/model/account/profile_ready.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the credential is attached before the profile is read', () async {
    var ready = false;
    var readAfterCredential = false;
    final profile = await waitForOwnProfile(
      ensureCredential: () async {
        ready = true;
      },
      read: () async {
        readAfterCredential = ready;
        return const ProfileRead(exists: true, data: {'username': 'ada'});
      },
      justCreated: true,
      checkActive: () {},
      budget: const Duration(milliseconds: 20),
      poll: const Duration(milliseconds: 1),
    );
    expect(readAfterCredential, isTrue);
    expect(profile?['username'], 'ada');
  });

  test('a refused read is retried until the new profile exists', () async {
    var reads = 0;
    final profile = await waitForOwnProfile(
      ensureCredential: () async {},
      read: () async {
        reads += 1;
        if (reads < 3) {
          throw FirebaseException(
            plugin: 'firestore',
            code: 'permission-denied',
          );
        }
        return const ProfileRead(exists: true, data: {'username': 'ada'});
      },
      justCreated: true,
      checkActive: () {},
      budget: const Duration(seconds: 2),
      poll: const Duration(milliseconds: 1),
    );
    expect(reads, 3);
    expect(profile?['username'], 'ada');
  });

  test(
    'a credential that is not ready yet still retries the profile',
    () async {
      final profile = await waitForOwnProfile(
        ensureCredential: () async => throw StateError('token not ready'),
        read: () async =>
            const ProfileRead(exists: true, data: {'username': 'ada'}),
        justCreated: true,
        checkActive: () {},
        budget: const Duration(milliseconds: 20),
        poll: const Duration(milliseconds: 1),
      );
      expect(profile?['username'], 'ada');
    },
  );

  test('a missing profile is not treated as a refusal', () async {
    final profile = await waitForOwnProfile(
      ensureCredential: () async {},
      read: () async => const ProfileRead(exists: false),
      justCreated: false,
      checkActive: () {},
      budget: const Duration(milliseconds: 15),
      poll: const Duration(milliseconds: 5),
    );
    expect(profile, isNull);
  });

  test(
    'a refusal that never clears is reported, not a missing account',
    () async {
      await expectLater(
        waitForOwnProfile(
          ensureCredential: () async {},
          read: () async =>
              throw FirebaseException(plugin: 'firestore', code: 'unavailable'),
          justCreated: false,
          checkActive: () {},
          budget: const Duration(milliseconds: 20),
          poll: const Duration(milliseconds: 5),
        ),
        throwsA(
          isA<FirebaseException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
    },
  );

  test('a definite refusal is not retried', () async {
    var reads = 0;
    await expectLater(
      waitForOwnProfile(
        ensureCredential: () async {},
        read: () async {
          reads += 1;
          throw FirebaseException(
            plugin: 'firestore',
            code: 'invalid-argument',
          );
        },
        justCreated: true,
        checkActive: () {},
        budget: const Duration(seconds: 2),
        poll: const Duration(milliseconds: 1),
      ),
      throwsA(isA<FirebaseException>()),
    );
    expect(reads, 1);
  });

  test('an account created moments ago is treated as a fresh sign-up', () {
    final now = DateTime.utc(2026, 11, 11, 12);
    expect(
      justCreatedAccount(_User(now), now: now.add(const Duration(seconds: 2))),
      isTrue,
    );
    expect(
      justCreatedAccount(
        _User(now.subtract(const Duration(minutes: 5))),
        now: now,
      ),
      isFalse,
    );
  });
}

class _User extends Fake implements User {
  _User(this.created);
  final DateTime created;
  @override
  UserMetadata get metadata => UserMetadata(
    created.millisecondsSinceEpoch,
    created.millisecondsSinceEpoch,
  );
}

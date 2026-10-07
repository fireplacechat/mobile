import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingDeleteUser extends Fake implements User {
  @override
  String get uid => 'dave-uid';
  @override
  String? get email => 'dave@users.fireplace.invalid';
  @override
  Future<void> delete() async =>
      throw FirebaseAuthException(code: 'requires-recent-login');
}

class _ThrowingDeleteCredential extends Fake implements UserCredential {
  @override
  final User user = _ThrowingDeleteUser();
}

/// Sign-up succeeds at the auth layer, the profile batch is rejected, and
/// undoing the half-created account then fails too.
class _DeleteFailsAuth extends Fake implements FirebaseAuth {
  bool signedOut = false;
  bool failSignOut = false;
  final _cred = _ThrowingDeleteCredential();

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async => _cred;

  @override
  Future<void> signOut() async {
    if (failSignOut) throw StateError('private transport details');
    signedOut = true;
  }
}

void main() {
  test('a half-created account that cannot be deleted is signed out', () async {
    final auth = _DeleteFailsAuth();
    // No invite document exists, so the profile batch is rejected and rollback runs.
    final service = AuthService(auth, FakeFirebaseFirestore());

    await expectLater(
      service.signUp(
        username: 'dave',
        password: 'correct horse',
        inviteCode: 'ABCD-EFGH-JKLM-NPQR',
      ),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          allOf(contains('unavailable'), isNot(contains('briefly'))),
        ),
      ),
    );
    expect(auth.signedOut, isTrue);
  });
  test(
    'failed rollback and failed sign-out still return a plain error',
    () async {
      final auth = _DeleteFailsAuth()..failSignOut = true;
      final service = AuthService(auth, FakeFirebaseFirestore());
      await expectLater(
        service.signUp(
          username: 'dave',
          password: 'correct horse',
          inviteCode: 'ABCD-EFGH-JKLM-NPQR',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('contact support'),
              isNot(contains('private transport')),
            ),
          ),
        ),
      );
      expect(auth.signedOut, isFalse);
    },
  );
}

import 'package:firebase_auth/firebase_auth.dart';

/// One read of `users/{uid}` while sign-in is still settling.
class ProfileRead {
  const ProfileRead({required this.exists, this.data});
  final bool exists;
  final Map<String, dynamic>? data;
}

/// Firestore codes that mean "the credential or the new profile is not ready",
/// rather than a definite refusal of a finished account.
const transientProfileCodes = <String>{
  'permission-denied',
  'unauthenticated',
  'unavailable',
  'deadline-exceeded',
  'aborted',
  'cancelled',
  'resource-exhausted',
};

const freshProfileBudget = Duration(seconds: 15);
const existingProfileBudget = Duration(seconds: 5);
const profilePoll = Duration(milliseconds: 250);

/// True when this Auth user was created moments ago.
///
/// Sign-up writes the Firestore profile after [createUserWithEmailAndPassword]
/// has already signed the app in. A brand-new account needs a longer wait than
/// a later sign-in, whose profile is already there.
bool justCreatedAccount(User user, {DateTime? now}) {
  final DateTime? created;
  try {
    created = user.metadata.creationTime;
  } catch (_) {
    return false;
  }
  if (created == null) return false;
  final age = (now ?? DateTime.now()).difference(created);
  return !age.isNegative && age < const Duration(minutes: 2);
}

/// Waits until this account's profile can be read.
///
/// Returns the document data when it exists (an empty map if the document has
/// no fields). Returns null when reads succeed and the document is still
/// missing, which the session treats as a half-deleted account. A transient
/// refusal that never clears is rethrown so the person can try again; it is
/// not treated as a missing account.
Future<Map<String, dynamic>?> waitForOwnProfile({
  required Future<void> Function() ensureCredential,
  required Future<ProfileRead> Function() read,
  required bool justCreated,
  required void Function() checkActive,
  Duration? budget,
  Duration poll = profilePoll,
}) async {
  // The ID token is not always attached to the first Firestore call after the
  // Auth user is created. A refused read then is the same race as a profile
  // that has not been committed yet.
  try {
    await ensureCredential().timeout(const Duration(seconds: 10));
  } catch (_) {}
  checkActive();
  final limit =
      budget ?? (justCreated ? freshProfileBudget : existingProfileBudget);
  final deadline = DateTime.now().add(limit);
  Object? lastTransient;
  while (true) {
    checkActive();
    try {
      final snap = await read();
      checkActive();
      if (snap.exists) return snap.data ?? const {};
      lastTransient = null;
    } on FirebaseException catch (e) {
      if (!transientProfileCodes.contains(e.code)) rethrow;
      lastTransient = e;
    }
    if (!DateTime.now().isBefore(deadline)) break;
    if (poll > Duration.zero) {
      await Future<void>.delayed(poll);
    }
  }
  if (lastTransient != null) throw lastTransient;
  return null;
}

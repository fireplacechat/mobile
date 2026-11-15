import 'package:cloud_firestore/cloud_firestore.dart';

/// The fields that must not stay on `users/{uid}` (decision 0055). Every
/// signed-in account can read a profile, so it holds only what other people
/// are meant to see.
///
/// - `invite`: the hash of the invite this account joined with. The rules
///   need it while the account is created, and never again.
/// - `lastActiveAt`: written by versions before 0.4.1. It told anyone who
///   knew the account's id when it was last in use.
const privateProfileFields = ['invite', 'lastActiveAt'];

/// Removes [privateProfileFields] from this account's own profile when
/// [profile], the document as just read, still has one. One write, once: after
/// sign-up, and once more for an account from an older version.
///
/// Returns whether a write was made. A failure is not an error for the
/// person: it is tried again the next time the app opens.
Future<bool> removePrivateProfileFields(
  FirebaseFirestore db,
  String uid,
  Map<String, dynamic>? profile,
) async {
  if (profile == null || !privateProfileFields.any(profile.containsKey)) {
    return false;
  }
  try {
    await db.collection('users').doc(uid).update({
      for (final field in privateProfileFields) field: FieldValue.delete(),
    });
    return true;
  } catch (_) {
    return false;
  }
}

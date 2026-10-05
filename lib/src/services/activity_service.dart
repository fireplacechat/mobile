import 'package:cloud_firestore/cloud_firestore.dart';

/// Records that this account is still in use, so the operator's retention sweep
/// (accounts inactive for 13 months are deleted) does not remove an active user.
///
/// The security rules only accept the server time here and at most one stamp per 12 hours,
/// so this skips the write when the stored stamp is recent. It is a courtesy write: failing
/// to record activity must never get in the way of using the app.
class ActivityService {
  ActivityService(this._db);
  final FirebaseFirestore _db;

  /// How often the stamp is refreshed (must stay above the 12-hour floor in the rules).
  static const refreshAfter = Duration(hours: 13);

  /// [profile] is the already-loaded `users/{uid}` document data, to avoid a second read.
  Future<bool> markActiveIfDue(
    String uid,
    Map<String, dynamic>? profile, {
    DateTime? now,
  }) async {
    final last = profile?['lastActiveAt'];
    final at = now ?? DateTime.now();
    if (last is Timestamp && at.difference(last.toDate()) < refreshAfter) {
      return false;
    }
    try {
      await _db.collection('users').doc(uid).update({
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Answers a rate-limit challenge by storing the token the server already sent.
///
/// The push handler calls [answer]. A failure must not escape that handler.
class PushChallenge {
  PushChallenge(FirebaseFirestore db) : _write = _bind(db);

  /// [write] replaces `users/{uid}/challengeProof/current`.
  /// Tests pass one that throws.
  PushChallenge.writing(this._write);

  final Future<void> Function(String uid, String token) _write;

  static final _challenge = RegExp(r'^[0-9a-f]{64}$');

  static Future<void> Function(String uid, String token) _bind(
    FirebaseFirestore db,
  ) {
    return (uid, token) => db
        .collection('users')
        .doc(uid)
        .collection('challengeProof')
        .doc('current')
        .set({'token': token});
  }

  /// Writes `{token: challenge}` when [data] is a challenge for [uid].
  ///
  /// [data] is the push data map. Returns whether the write finished.
  /// Never throws.
  Future<bool> answer(Map<String, String> data, String uid) async {
    try {
      if (uid.isEmpty) return false;
      final challenge = data['challenge'];
      if (data['type'] != 'rateLimitChallenge') return false;
      if (challenge == null || !_challenge.hasMatch(challenge)) return false;
      await _write(uid, challenge);
      return true;
    } catch (_) {
      return false;
    }
  }
}

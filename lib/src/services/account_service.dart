// ignore_for_file: prefer_initializing_formals
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'auth_service.dart';
import 'secret_store.dart';

/// Deletes the signed-in account and the personal data stored for it.
///
/// Steps (each is safe to repeat, so an interrupted deletion can be finished):
///  1. re-authenticate with the password,
///  2. flag the profile as `deleting` (so the app resumes deletion, not normal use),
///  3. delete every message this account sent,
///  4. delete devices (with their prekeys), the recovery backup, link requests, blocks,
///  5. release the username and delete the profile,
///  6. stop the running session and erase all local keys and history,
///  7. delete the Firebase Auth user.
///
/// Kept on purpose: reports filed about or by this account (needed to handle
/// abuse), and other people's own messages to this account (they cannot be
/// read any more: the keys are gone). The other participant's app removes the
/// emptied conversation when it notices the profile is gone.
class AccountService {
  AccountService({
    required FirebaseAuth auth,
    required FirebaseFirestore db,
    required SecretStore secrets,
    Future<void> Function()? stopSession,
    Future<void> Function()? destroyLocalData,
    Future<void> Function(User user, String password)? reauthenticate,
    void Function(String step)? onStep,
  }) : _auth = auth,
       _db = db,
       _secrets = secrets,
       _stopSession = stopSession,
       _destroyLocalData = destroyLocalData,
       _reauth = reauthenticate,
       _onStep = onStep;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final SecretStore _secrets;
  final Future<void> Function()? _stopSession;
  final Future<void> Function()? _destroyLocalData;
  final Future<void> Function(User user, String password)? _reauth;
  final void Function(String step)? _onStep;

  static const steps = [
    'reauth',
    'mark',
    'messages',
    'devices',
    'private',
    'profile',
    'local',
    'auth',
  ];

  Future<void> deleteAccount({required String password}) async {
    final user = _auth.currentUser;
    if (user == null) throw AuthException('Not signed in.');
    final uid = user.uid;

    _onStep?.call('reauth');
    try {
      if (_reauth != null) {
        await _reauth(user, password);
      } else {
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: user.email!, password: password),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (const {
        'wrong-password',
        'invalid-credential',
        'invalid-email',
      }.contains(e.code)) {
        throw AuthException('That password is not correct.');
      }
      throw AuthException(e.message ?? 'Could not confirm your password.');
    }

    final profileRef = _db.collection('users').doc(uid);

    _onStep?.call('mark');
    final profile = await profileRef.get();
    final username = profile.data()?['username'] as String?;
    if (profile.exists && profile.data()?['deleting'] != true) {
      await profileRef.update({'deleting': true});
    }

    _onStep?.call('messages');
    final chats = await _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .get();
    for (final chat in chats.docs) {
      await _deleteQuery(
        chat.reference
            .collection('messages')
            .where('senderUid', isEqualTo: uid),
      );
    }

    _onStep?.call('devices');
    final devices = await profileRef.collection('devices').get();
    for (final d in devices.docs) {
      await _deleteQuery(d.reference.collection('prekeys'));
      await d.reference.delete();
    }

    _onStep?.call('private');
    await _deleteQuery(profileRef.collection('pushTokens'));
    await profileRef.collection('private').doc('backup').delete();
    await _deleteQuery(profileRef.collection('linkRequests'));
    await _deleteQuery(profileRef.collection('blocks'));
    await _deleteQuery(profileRef.collection('limits'));

    _onStep?.call('profile');
    if (username != null) {
      final nameRef = _db.collection('usernames').doc(username);
      final name = await nameRef.get();
      if (name.exists && name.data()?['uid'] == uid) await nameRef.delete();
    }
    await profileRef.delete();

    _onStep?.call('local');
    await _stopSession?.call();
    await _destroyLocalData?.call();
    await _secrets.clear();

    _onStep?.call('auth');
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      throw AuthException(
        'Your data is deleted but the sign-in account could not be removed '
        '(${e.message ?? e.code}). Sign in again and retry.',
      );
    }
  }

  Future<void> _deleteQuery(Query<Map<String, dynamic>> q) async {
    while (true) {
      final snap = await q.limit(400).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }
}

// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:fireplace/src/model/account/auth_service.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/account_erasure.dart';
import 'package:fireplace/src/model/settings/account_preferences.dart';

/// Deletes the signed-in account and the personal data stored for it.
///
/// Steps (each is safe to repeat, so an interrupted deletion can be finished):
///  1. re-authenticate with the password,
///  2. flag the profile as `deleting` (so the app resumes deletion, not normal use),
///  3. stop the running session and freeze this account's preferences,
///  4. erase only this account's local history, settings and keychain entries,
///  5. ask the server to delete the rest (decision 0066) and wait for it,
///  6. or, when the server does not take the request, delete the rest here:
///     sent messages, devices/prekeys, backup, named private records, the
///     invite codes it made for others, the username, the profile and the
///     Firebase Auth user,
///  7. explicitly sign out.
///
/// Kept on purpose: other people's own messages to this account (they cannot be
/// read any more: the keys are gone), and spam reports, which name accounts and
/// do not contain messages. Another account's local history is not erased.
class AccountService {
  AccountService({
    required FirebaseAuth auth,
    required FirebaseFirestore db,
    required SecretStore secrets,
    Future<void> Function()? stopSession,
    Future<void> Function()? destroyLocalData,
    Future<void> Function(User user, String password)? reauthenticate,
    void Function(String step)? onStep,
    Future<void> Function()? onMarked,
    AccountPreferences? preferences,
    this.serverPickup = const Duration(seconds: 15),
    this.serverFinish = const Duration(seconds: 60),
  }) : _auth = auth,
       _db = db,
       _secrets = secrets,
       _stopSession = stopSession,
       _destroyLocalData = destroyLocalData,
       _reauth = reauthenticate,
       _onStep = onStep,
       _onMarked = onMarked,
       _preferences = preferences ?? AccountPreferences(secrets);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final SecretStore _secrets;
  final Future<void> Function()? _stopSession;
  final Future<void> Function()? _destroyLocalData;
  final Future<void> Function(User user, String password)? _reauth;
  final void Function(String step)? _onStep;
  final Future<void> Function()? _onMarked;
  final AccountPreferences _preferences;

  /// How long the server has to take a deletion request, and then to finish
  /// it, before the app deletes the rest itself.
  final Duration serverPickup, serverFinish;
  // Session invalidation may rebuild the provider while cleanup is running.
  // Keep one operation per Auth instance/UID across those service instances.
  static final _operations = Expando<Map<String, Future<void>>>();

  /// The steps when the server finishes the deletion.
  static const serverSteps = [
    'reauth',
    'mark',
    'stop',
    'local',
    'server',
    'signout',
  ];

  /// The steps when the app deletes the rest itself.
  static const steps = [
    'reauth',
    'mark',
    'stop',
    'local',
    'server',
    'messages',
    'devices',
    'private',
    'profile',
    'auth',
    'signout',
  ];

  Future<void> deleteAccount({required String password}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Future.error(AuthException('Not signed in.'));
    final operations = _operations[_auth] ??= {};
    return operations.putIfAbsent(
      uid,
      () => _deleteAccount(password).whenComplete(() {
        operations.remove(uid);
      }),
    );
  }

  void _requireAccount(String uid) {
    if (_auth.currentUser?.uid != uid) {
      throw AuthException(
        'The signed-in account changed. Sign in again to finish deleting.',
      );
    }
  }

  Future<void> _deleteAccount(String password) async {
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
    _requireAccount(uid);
    final profile = await profileRef.get(
      const GetOptions(source: Source.server),
    );
    final username =
        profile.data()?['username'] as String? ??
        (user.email?.endsWith('@${AuthService.emailDomain}') == true
            ? user.email!.split('@').first
            : null);
    _requireAccount(uid);
    if (profile.exists && profile.data()?['deleting'] != true) {
      await profileRef.update({'deleting': true});
    }
    await _onMarked?.call();
    _onStep?.call('stop');
    await _stopSession?.call();
    await _preferences.deleting(uid);

    _onStep?.call('local');
    _requireAccount(uid);
    await _destroyLocalData?.call();
    await eraseAccountSecrets(_secrets, uid);

    _onStep?.call('server');
    _requireAccount(uid);
    if (!await _finishOnServer(uid)) {
      await _deleteRest(user, uid, profileRef, username);
    }

    _onStep?.call('signout');
    // Firebase normally clears this user on delete, but explicitly clear the
    // local auth session too. Never sign out an account selected meanwhile.
    if (_auth.currentUser == null || _auth.currentUser?.uid == uid) {
      await _auth.signOut();
    }
  }

  /// Asks the server to delete what is left (decision 0066), and waits until
  /// it has: the server deletes the request last. False when the server does
  /// not take it (an older backend refuses the request, the phone is offline,
  /// or nothing picks it up in time); the app then deletes the rest itself.
  /// Both ways can overlap safely, since every step can run again.
  Future<bool> _finishOnServer(String uid) async {
    final ref = _db.collection('deletionRequests').doc(uid);
    try {
      // Offline, a write waits for the server without end.
      await ref.set({'at': FieldValue.serverTimestamp()}).timeout(serverPickup);
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') return false;
      // Refused: an older backend, or a request from an earlier attempt that
      // the server is still working on (a request cannot be written twice).
      final earlier = await ref.get(const GetOptions(source: Source.server));
      if (!earlier.exists) return false;
    } on Object {
      return false; // offline (timed out), or anything else: do it here
    }
    final taken = Completer<void>();
    final finished = Completer<void>();
    final sub = ref.snapshots().listen(
      (snap) {
        if (snap.metadata.isFromCache) return;
        if (!snap.exists) {
          if (!taken.isCompleted) taken.complete();
          if (!finished.isCompleted) finished.complete();
        } else if (snap.data()?['startedAt'] != null && !taken.isCompleted) {
          taken.complete();
        }
      },
      onError: (Object e) {
        if (!finished.isCompleted) finished.completeError(e);
        if (!taken.isCompleted) taken.completeError(e);
      },
    );
    try {
      await taken.future.timeout(serverPickup);
      await finished.future.timeout(serverFinish);
      return true;
    } on Object {
      return false;
    } finally {
      await sub.cancel();
    }
  }

  /// What the server would delete, done from the phone through the rules, as
  /// apps did before decision 0066.
  Future<void> _deleteRest(
    User user,
    String uid,
    DocumentReference<Map<String, dynamic>> profileRef,
    String? username,
  ) async {
    _onStep?.call('messages');
    final chats = await _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .get(const GetOptions(source: Source.server));
    for (final chat in chats.docs) {
      await _deleteQuery(
        chat.reference
            .collection('messages')
            .where('senderUid', isEqualTo: uid),
      );
    }

    _onStep?.call('devices');
    final devices = await profileRef
        .collection('devices')
        .get(const GetOptions(source: Source.server));
    for (final d in devices.docs) {
      await _deleteQuery(d.reference.collection('prekeys'));
      await d.reference.delete();
    }

    _onStep?.call('private');
    await _deleteQuery(profileRef.collection('pushTokens'));
    await profileRef.collection('private').doc('backup').delete();
    await _deleteQuery(profileRef.collection('linkRequests'));
    await _deleteQuery(profileRef.collection('blocks'));
    // The rules deliberately forbid listing counters. Delete their three
    // named documents, and the challenge proof, through owner-only deletes.
    for (final name in ['send', 'chats', 'claims']) {
      await profileRef.collection('limits').doc(name).delete();
    }
    await profileRef.collection('challengeProof').doc('current').delete();
    await _deleteInviteRows(profileRef);

    _onStep?.call('profile');
    if (username != null) {
      final nameRef = _db.collection('usernames').doc(username);
      final name = await nameRef.get(const GetOptions(source: Source.server));
      if (name.exists && name.data()?['uid'] == uid) {
        await _deleteOrGone(nameRef, stillThere: (d) => d['uid'] == uid);
      }
    }
    await profileRef.delete();

    _onStep?.call('auth');
    _requireAccount(uid);
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      // The server finished after all, while this ran.
      if (e.code == 'user-not-found') return;
      throw AuthException(
        'Your data is deleted but the sign-in account could not be removed '
        '(${e.message ?? e.code}). Sign in again and retry.',
      );
    }
  }

  /// The codes this account made for other people (decision 0049). Each row
  /// holds a code in clear, so it goes with the account; an unused code's
  /// invite goes too. A used invite stays, and the rules refuse to delete it.
  /// The server already refuses every code of a deleting account, so a retry
  /// may find an invite gone or not deletable; neither stops the deletion.
  Future<void> _deleteInviteRows(
    DocumentReference<Map<String, dynamic>> profileRef,
  ) async {
    final rows = await profileRef
        .collection('inviteSlots')
        .get(const GetOptions(source: Source.server));
    for (final row in rows.docs) {
      final invite = row.data()['invite'];
      if (row.data()['used'] != true && invite is String) {
        try {
          await _db.collection('invites').doc(invite).delete();
        } on FirebaseException catch (e) {
          if (e.code != 'permission-denied' && e.code != 'not-found') rethrow;
        }
      }
      await row.reference.delete();
    }
  }

  // Firestore sends a pending write again when the connection drops before
  // the server answers. If the first send had worked, the second deletes
  // documents that are gone, and the rules for messages and usernames refuse
  // that (they read `resource.data`, which is null then). So a refused delete
  // is checked against the server: gone means an earlier send did it (issue
  // 119). Still there means a real refusal, which stops the deletion.

  /// Deletes [q]'s documents a page at a time.
  Future<void> _deleteQuery(Query<Map<String, dynamic>> q) async {
    FirebaseException? refusal;
    var refusedPaths = const <String>{};
    while (true) {
      final snap = await q
          .limit(400)
          .get(const GetOptions(source: Source.server));
      if (snap.docs.isEmpty) return;
      final paths = {for (final d in snap.docs) d.reference.path};
      if (refusal != null && paths.any(refusedPaths.contains)) throw refusal;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      try {
        await batch.commit();
        refusal = null;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
        // A batch is all or nothing: the next page shows which it was.
        (refusal, refusedPaths) = (e, paths);
      }
    }
  }

  /// Deletes [ref]; a refusal counts only if [stillThere] says the document
  /// on the server is still the one being deleted.
  Future<void> _deleteOrGone(
    DocumentReference<Map<String, dynamic>> ref, {
    required bool Function(Map<String, dynamic> data) stillThere,
  }) async {
    try {
      await ref.delete();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      final now = await ref.get(const GetOptions(source: Source.server));
      final data = now.data();
      if (data != null && stillThere(data)) rethrow;
    }
  }
}

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Username + password on top of Firebase email/password auth.
/// The email is synthetic (`<username>@users.fireplace.invalid`); it is never
/// shown or used for mail, and the Firestore rules require it to match the username.
class AuthService {
  AuthService(this._auth, this._db, {this._beforeSignOut});
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final Future<void> Function()? _beforeSignOut;

  static const emailDomain = 'users.fireplace.invalid';
  static final _usernameRe = RegExp(r'^[a-z0-9_]{3,20}$');
  static const minPasswordLength = 8;

  static String normalize(String username) => username.trim().toLowerCase();
  static String emailFor(String username) =>
      '${normalize(username)}@$emailDomain';
  static bool isValidUsername(String u) => _usernameRe.hasMatch(normalize(u));

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Invite codes look like `ABCD-EFGH-JKLM-NPQR` (16 characters of A-Z, 2-7).
  /// Dashes, spaces and case are ignored.
  static String? normalizeInvite(String input) {
    final c = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    return RegExp(r'^[A-Z2-7]{16}$').hasMatch(c) ? c : null;
  }

  /// The invite document id: SHA-256 (hex) of the normalized code, so the code
  /// itself is never stored on the server.
  static Future<String> inviteHash(String normalizedCode) async {
    final h = await Sha256().hash(utf8.encode(normalizedCode));
    return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<User> signUp({
    required String username,
    required String password,
    required String inviteCode,
    String? displayName,
  }) async {
    final name = normalize(username);
    if (!isValidUsername(name)) {
      throw AuthException('Usernames are 3-20 characters: a-z, 0-9 and _.');
    }
    if (password.length < minPasswordLength) {
      throw AuthException(
        'Password must be at least $minPasswordLength characters.',
      );
    }
    final code = normalizeInvite(inviteCode);
    if (code == null) {
      throw AuthException(
        "That doesn't look like an invite code. It has 16 letters and "
        'numbers, like ABCD-EFGH-JKLM-NPQR.',
      );
    }
    final inviteId = await inviteHash(code);
    final UserCredential cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: emailFor(name),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw AuthException('That username is taken.');
      }
      throw AuthException(e.message ?? 'Sign-up failed.');
    }
    final user = cred.user!;
    try {
      final batch = _db.batch();
      batch.set(_db.collection('usernames').doc(name), {'uid': user.uid});
      batch.set(_db.collection('users').doc(user.uid), {
        'username': name,
        'displayName': (displayName ?? name).trim().isEmpty
            ? name
            : (displayName ?? name).trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'invite': inviteId,
      });
      // Claiming the invite is part of the same atomic write: the rules accept the
      // profile only if this invite exists and is unused.
      batch.update(_db.collection('invites').doc(inviteId), {
        'usedBy': user.uid,
        'usedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } on FirebaseException catch (e) {
      // Invite invalid/used, or name already claimed: undo the auth account.
      await user.delete();
      throw AuthException(
        e.code == 'permission-denied' || e.code == 'not-found'
            ? 'That invite code is invalid or already used.'
            : 'Sign-up failed: ${e.message}',
      );
    }
    return user;
  }

  Future<User> signIn({
    required String username,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: emailFor(username),
        password: password,
      );
      return cred.user!;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-disabled') {
        throw AuthException(
          'This account has been suspended for breaking the Fireplace rules.',
        );
      }
      // Same message for unknown user and wrong password.
      if (const {
        'user-not-found',
        'wrong-password',
        'invalid-credential',
        'invalid-email',
      }.contains(e.code)) {
        throw AuthException('Wrong username or password.');
      }
      throw AuthException(e.message ?? 'Sign-in failed.');
    }
  }

  /// Changes the account password. Message keys are independent of the password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw AuthException('Not signed in.');
    }
    if (newPassword.length < minPasswordLength) {
      throw AuthException(
        'Password must be at least $minPasswordLength characters.',
      );
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        ),
      );
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      if (const {'wrong-password', 'invalid-credential'}.contains(e.code)) {
        throw AuthException('Current password is wrong.');
      }
      throw AuthException(e.message ?? 'Could not change password.');
    }
  }

  Future<void> signOut() async {
    try {
      await _beforeSignOut?.call();
    } catch (_) {
      // Local cleanup is best-effort; it must not prevent the user signing out.
    }
    await _auth.signOut();
  }
}

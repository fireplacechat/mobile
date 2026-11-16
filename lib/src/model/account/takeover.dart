import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/crypto/device_proof.dart';
import 'package:fireplace/src/model/account/auth_service.dart';
import 'package:fireplace/src/model/keys/key_service.dart';

/// How long a new phone waits before it can start fresh on an account that
/// has a device (decision 0063).
enum LostPhoneWait {
  oneDay(Duration(days: 1), '1 day'),
  threeDays(Duration(days: 3), '3 days'),
  oneWeek(Duration(days: 7), '1 week'),
  twoWeeks(Duration(days: 14), '2 weeks'),
  thirtyDays(Duration(days: 30), '30 days');

  const LostPhoneWait(this.length, this.label);
  final Duration length;
  final String label;

  static const standard = threeDays;

  static LostPhoneWait fromDays(Object? days) =>
      values.where((w) => w.length.inDays == days).firstOrNull ?? standard;
}

/// A new phone has asked to start fresh and is waiting.
class PendingStart {
  const PendingStart({required this.startedAt, required this.readyAt});
  final DateTime startedAt;
  final DateTime readyAt;

  bool readyBy(DateTime now) => !now.isBefore(readyAt);
}

class TakeoverException implements Exception {
  TakeoverException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Starting fresh with a wait, and what a device of the account can do about
/// it. The server enforces all of it; this only asks.
class TakeoverService {
  TakeoverService(this._db, this._auth, {Duration? timeout})
    : _timeout = timeout ?? const Duration(seconds: 30);

  final FirebaseFirestore _db;
  final AuthService _auth;
  final Duration _timeout;

  DocumentReference<Map<String, dynamic>> _pending(String uid) =>
      _db.doc('users/$uid/private/startFresh');
  DocumentReference<Map<String, dynamic>> _security(String uid) =>
      _db.doc('users/$uid/private/security');

  /// The server stamps `startedAt` and holds `waitDays` to the account's
  /// setting; the end of the wait follows from the two.
  static PendingStart? _parse(Map<String, dynamic>? data) {
    final started = data?['startedAt'], days = data?['waitDays'];
    if (started is! Timestamp || days is! int) return null;
    final at = started.toDate();
    return PendingStart(
      startedAt: at,
      readyAt: at.add(Duration(days: days)),
    );
  }

  /// The start that is waiting on this account, if any.
  Stream<PendingStart?> watch(String uid) =>
      _pending(uid).snapshots().map((s) => _parse(s.data()));

  Future<PendingStart?> pending(String uid) async =>
      _parse((await _pending(uid).get()).data());

  Future<LostPhoneWait> wait(String uid) async =>
      LostPhoneWait.fromDays((await _security(uid).get()).data()?['waitDays']);

  /// Whether the account has any device: without one there is nobody to
  /// warn, and starting fresh does not wait.
  Future<bool> hasDevices(String uid) async =>
      (await _db.collection('users/$uid/devices').limit(1).get())
          .docs
          .isNotEmpty;

  /// A new phone asks to start fresh. The server stamps the time and works
  /// out when the wait ends.
  Future<PendingStart> start(String uid) async {
    final wait = await this.wait(uid);
    await _pending(uid).set({
      'startedAt': FieldValue.serverTimestamp(),
      'waitDays': wait.length.inDays,
      'session': await _auth.signInTime(),
    });
    final made = await pending(uid);
    if (made == null) {
      throw TakeoverException('Could not start. Try again.');
    }
    return made;
  }

  /// The new phone changes its mind.
  Future<void> withdraw(String uid) => _pending(uid).delete();

  /// A device of the account changes how long a new phone must wait.
  Future<void> setWait(String uid, LocalDevice device, LostPhoneWait wait) =>
      _deviceRequest(
        uid,
        device,
        'setWait',
        ['${wait.length.inDays}'],
        {'waitDays': wait.length.inDays},
      );

  /// A device of the account removes another one. Where the server does not
  /// check device requests yet, [direct] marks it removed as before.
  Future<void> removeDevice(
    String uid,
    LocalDevice device,
    String target, {
    required Future<void> Function() direct,
  }) async {
    if (!(await _db.doc('config/deviceProof').get()).exists) return direct();
    await _deviceRequest(
      uid,
      device,
      'removeDevice',
      [target],
      {'target': target},
    );
  }

  /// A device of the account stops the waiting start. The password is asked
  /// for again, which a stolen phone cannot answer, and then replaced, since
  /// whoever started this knows the old one.
  Future<void> stop(
    String uid,
    LocalDevice device, {
    required String password,
    required String newPassword,
  }) async {
    if (newPassword.length < AuthService.minPasswordLength) {
      throw TakeoverException(
        'Use at least ${AuthService.minPasswordLength} characters.',
      );
    }
    try {
      await _auth.confirmPassword(password);
    } on AuthException {
      throw TakeoverException('That password is not right.');
    }
    await _deviceRequest(uid, device, 'stop', const [], const {});
    try {
      await _auth.changePassword(
        currentPassword: password,
        newPassword: newPassword,
      );
    } on AuthException catch (e) {
      throw TakeoverException(
        'Stopped, but the password was not changed: ${e.message}',
      );
    }
  }

  /// A request only a device may make: it carries a proof made with the
  /// device's key, which the server checks before it acts.
  Future<void> _deviceRequest(
    String uid,
    LocalDevice device,
    String kind,
    List<String> arguments,
    Map<String, Object> fields,
  ) async {
    final server = (await _db.doc('config/deviceProof').get())
        .data()?['x25519Pub'];
    if (server is! String) {
      throw TakeoverException('Not available yet. Try again later.');
    }
    final id = b64(randomBytes(12)).replaceAll('+', '-').replaceAll('/', '_');
    final proof = await DeviceProof.make(
      deviceSeed: device.keys.x25519Seed,
      devicePub: device.keys.x25519Pub,
      serverPub: base64Decode(server),
      message: DeviceProof.message(
        uid: uid,
        deviceId: device.keys.deviceId,
        requestId: id,
        kind: kind,
        arguments: arguments,
      ),
    );
    final ref = _db.doc('users/$uid/accountOps/$id');
    await ref.set({
      'kind': kind,
      'device': device.keys.deviceId,
      'proof': b64(proof),
      'at': FieldValue.serverTimestamp(),
      ...fields,
    });
    final done = Completer<void>();
    final sub = ref.snapshots().listen(
      (snap) {
        final status = snap.data()?['status'];
        if (done.isCompleted) return;
        if (status == 'done') done.complete();
        if (status == 'refused') {
          done.completeError(TakeoverException('That was refused. Try again.'));
        }
      },
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      },
    );
    try {
      await done.future.timeout(_timeout);
    } on TimeoutException {
      throw TakeoverException('No answer yet. Check your connection.');
    } finally {
      await sub.cancel();
    }
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../crypto/device.dart';
import '../crypto/identity.dart';
import '../crypto/link.dart';
import '../crypto/recovery.dart';
import 'key_service.dart';
import 'secret_store.dart';

class RecoveryException implements Exception {
  RecoveryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What the new device shows while waiting for an existing device to approve it.
class LinkRequest {
  LinkRequest(this.uid, this.keys, this.qrPayload);
  final String uid;
  final DeviceKeys keys;
  final String qrPayload;
}

/// Parsed QR code `fireplace://link/1/<uid>/<deviceId>/<fingerprint>`.
class LinkQr {
  LinkQr(this.uid, this.deviceId, this.fingerprint);
  final String uid, deviceId, fingerprint;

  String encode() => 'fireplace://link/1/$uid/$deviceId/$fingerprint';

  static final _re = RegExp(
    r'^fireplace://link/1/([A-Za-z0-9]{1,128})/([A-Za-z0-9_-]{8,64})/([A-Za-z0-9_-]{16,32})$',
  );

  static LinkQr? parse(String? raw) {
    final m = _re.firstMatch((raw ?? '').trim());
    return m == null ? null : LinkQr(m.group(1)!, m.group(2)!, m.group(3)!);
  }
}

/// Recovery key backups, new-device linking, and identity reset.
class RecoveryService {
  /// A QR code is only honoured for this long after the new device showed it.
  static const linkRequestLifetime = Duration(minutes: 15);

  RecoveryService(this._db, this._store, this._keys);
  final FirebaseFirestore _db;
  final SecretStore _store;
  final KeyService _keys;

  DocumentReference<Map<String, dynamic>> _backup(String uid) =>
      _db.collection('users').doc(uid).collection('private').doc('backup');
  CollectionReference<Map<String, dynamic>> _requests(String uid) =>
      _db.collection('users').doc(uid).collection('linkRequests');

  // ------------------------------------------------------------ recovery key

  Future<bool> hasBackup(String uid) async => (await _backup(uid).get()).exists;

  /// Creates (or replaces) the backup. The returned key must be shown to the
  /// user once; it is never stored anywhere.
  Future<RecoveryKey> createBackup(String uid, AccountIdentity identity) async {
    final key = RecoveryKey.generate();
    await _backup(uid).set({
      'blob': await RecoveryBackup.encrypt(identity, key),
      'v': 1,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return key;
  }

  /// Sets up THIS install as a new device using the account identity from the backup.
  Future<LocalDevice> restoreWithRecoveryKey(String uid, String input) async {
    final key = await RecoveryKey.parse(input);
    if (key == null) {
      throw RecoveryException(
        'That recovery key is not valid. Check for typos.',
      );
    }
    final snap = await _backup(uid).get();
    if (!snap.exists) {
      throw RecoveryException('This account has no recovery key backup.');
    }
    final AccountIdentity identity;
    try {
      identity = await RecoveryBackup.decrypt(
        snap.data()!['blob'] as String,
        key,
      );
    } on BackupException {
      throw RecoveryException('That recovery key does not match this account.');
    }
    return _keys.installDevice(uid, identity, await DeviceKeys.generate());
  }

  /// Last resort when the identity is lost: remove all devices and the backup and
  /// start with a brand-new identity. Contacts will see a security-code change.
  Future<LocalDevice> resetIdentity(String uid) async {
    for (final d
        in (await _db.collection('users').doc(uid).collection('devices').get())
            .docs) {
      await d.reference.delete();
    }
    await _backup(uid).delete();
    for (final k in ['identity', 'device', 'bundle']) {
      await _store.delete('$k:$uid');
    }
    return _keys.installDevice(
      uid,
      await AccountIdentity.generate(),
      await DeviceKeys.generate(),
    );
  }

  // ------------------------------------------------- linking: the NEW device

  Future<LinkRequest> startLink(String uid) async {
    final keys = await DeviceKeys.generate();
    final fp = await LinkCrypto.requestFingerprint(keys.x25519Pub, keys.kemPub);
    await _requests(uid).doc(keys.deviceId).set({
      'x25519Pub': base64Encode(keys.x25519Pub),
      'kemPub': base64Encode(keys.kemPub),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return LinkRequest(uid, keys, LinkQr(uid, keys.deviceId, fp).encode());
  }

  /// Completes when an existing device has written its sealed response.
  Future<SealedIdentity> awaitResponse(
    LinkRequest req, {
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final snap = await _requests(req.uid)
        .doc(req.keys.deviceId)
        .snapshots()
        .firstWhere((s) => s.data()?['response'] != null)
        .timeout(
          timeout,
          onTimeout: () => throw RecoveryException('Linking timed out.'),
        );
    return SealedIdentity.fromJson(
      Map<String, dynamic>.from(snap.data()!['response']),
    );
  }

  /// The confirmation code the new device expects to see on the approving device.
  /// Throws if [typedCode] doesn't match, so a swapped identity is never installed.
  Future<LocalDevice> completeLink(
    LinkRequest req,
    SealedIdentity sealed,
    String typedCode,
  ) async {
    final identity = await LinkCrypto.open(
      sealed,
      uid: req.uid,
      keys: req.keys,
    );
    final expected = await LinkCrypto.confirmationCode(
      identity.publicBytes,
      req.keys.x25519Pub,
      req.keys.kemPub,
    );
    if (typedCode.trim() != expected) {
      throw RecoveryException(
        'The code does not match. Do not continue unless you can explain why.',
      );
    }
    final device = await _keys.installDevice(req.uid, identity, req.keys);
    await _requests(req.uid).doc(req.keys.deviceId).delete();
    return device;
  }

  Future<void> cancelLink(LinkRequest req) =>
      _requests(req.uid).doc(req.keys.deviceId).delete();

  // --------------------------------------------- linking: the APPROVING device

  /// Scans the new device's QR. Returns the confirmation code to display.
  Future<String> approveLink(
    String uid,
    AccountIdentity identity,
    String qrPayload,
  ) async {
    final qr = LinkQr.parse(qrPayload);
    if (qr == null) {
      throw RecoveryException("That isn't a Fireplace link code.");
    }
    if (qr.uid != uid) {
      throw RecoveryException('That code belongs to a different account.');
    }
    final snap = await _requests(uid).doc(qr.deviceId).get();
    if (!snap.exists) throw RecoveryException('This link request has expired.');
    final data = snap.data()!;
    final made = data['createdAt'];
    if (made is Timestamp &&
        DateTime.now().difference(made.toDate()) > linkRequestLifetime) {
      throw RecoveryException(
        'This link request has expired. Start again on the new device.',
      );
    }
    if (data['response'] != null) {
      throw RecoveryException('This request was already answered.');
    }
    final x = base64Decode(data['x25519Pub'] as String);
    final k = base64Decode(data['kemPub'] as String);
    // The QR carries a fingerprint of the keys, so a tampered server copy is caught.
    if (await LinkCrypto.requestFingerprint(x, k) != qr.fingerprint) {
      throw RecoveryException(
        'The keys on the server do not match the QR code. Cancel and try again.',
      );
    }
    final sealed = await LinkCrypto.seal(
      identity,
      uid: uid,
      deviceId: qr.deviceId,
      x25519Pub: x,
      kemPub: k,
    );
    await _requests(uid).doc(qr.deviceId).update({'response': sealed.toJson()});
    return LinkCrypto.confirmationCode(identity.publicBytes, x, k);
  }
}

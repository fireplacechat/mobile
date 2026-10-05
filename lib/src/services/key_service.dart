import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../crypto/codec.dart';
import '../crypto/device.dart';
import '../crypto/identity.dart';
import 'secret_store.dart';

/// This account already has devices but this install has no keys. Recovery or
/// device linking (build plan Phase 6) is required.
class NeedsRecoveryException implements Exception {
  @override
  String toString() =>
      'This account has other devices; link or recover to use this one.';
}

/// A contact's account identity no longer matches the one we pinned.
class IdentityChangedException implements Exception {
  IdentityChangedException(this.peerUid, this.newIdentityPub);
  final String peerUid;
  final List<int> newIdentityPub;
  @override
  String toString() =>
      'Security warning: the identity key of $peerUid changed.';
}

/// This device was revoked from another device of the same account.
class DeviceRevokedException implements Exception {
  @override
  String toString() => 'This device was removed from your account.';
}

class DeviceInfo {
  DeviceInfo(this.deviceId, this.createdAt, this.revoked, this.isThisDevice);
  final String deviceId;
  final DateTime? createdAt;
  final bool revoked;
  final bool isThisDevice;
}

class LocalDevice {
  LocalDevice(this.identity, this.keys, this.bundle);
  final AccountIdentity identity;
  final DeviceKeys keys;
  final DeviceBundle bundle;
}

class KeyService {
  KeyService(this._db, this._store);
  final FirebaseFirestore _db;
  final SecretStore _store;
  String? _accountUid;
  AccountIdentity? _localIdentity;

  void _bindAccount(String uid) {
    if (_accountUid != null && _accountUid != uid) {
      throw StateError('Use a separate key service for each account.');
    }
    _accountUid = uid;
  }

  /// Bind a session's already-loaded local device to its account context.
  /// Recovery/linking and session restarts may hand a certified device directly
  /// to ChatService rather than reloading it from storage.
  void bindLocalDevice(String uid, LocalDevice device) {
    _bindAccount(uid);
    if (_localIdentity != null &&
        !bytesEqual(_localIdentity!.publicBytes, device.identity.publicBytes)) {
      throw StateError(
        'Use a new key service when replacing the local identity.',
      );
    }
    _localIdentity = device.identity;
  }

  String _trustKey(String kind, String peerUid) {
    final uid = _accountUid;
    if (uid == null || _localIdentity == null) {
      throw StateError('Load the local identity before using contact trust.');
    }
    return '$kind:account:${jsonEncode([uid, peerUid])}';
  }

  CollectionReference<Map<String, dynamic>> _devices(String uid) =>
      _db.collection('users').doc(uid).collection('devices');

  /// Loads this device's keys, or generates and publishes them on first run.
  Future<LocalDevice> ensureDevice(String uid) async {
    _bindAccount(uid);
    final idJson = await _store.read('identity:$uid');
    final devJson = await _store.read('device:$uid');
    final bundleJson = await _store.read('bundle:$uid');
    if (idJson != null && devJson != null && bundleJson != null) {
      final AccountIdentity identity;
      final DeviceKeys keys;
      final DeviceBundle bundle;
      try {
        identity = AccountIdentity.fromJson(jsonDecode(idJson));
        keys = DeviceKeys.fromJson(jsonDecode(devJson));
        bundle = DeviceBundle.fromFirestore(
          uid,
          keys.deviceId,
          Map<String, dynamic>.from(jsonDecode(bundleJson)),
        );
        // Public and private halves must belong together and the certificate must still
        // verify. A corrupted or half-restored record is never used, and a new identity
        // is never minted on top of an account that already has published keys.
        final consistent =
            await keys.consistent() &&
            await identity.consistent() &&
            bytesEqual(bundle.x25519Pub, keys.x25519Pub) &&
            bytesEqual(bundle.kemPub, keys.kemPub) &&
            bytesEqual(bundle.identityPub, identity.publicBytes) &&
            await bundle.verifyCert();
        if (!consistent) throw const FormatException('inconsistent local keys');
      } catch (_) {
        throw NeedsRecoveryException(); // recover or link instead of guessing
      }
      final mine = await _devices(uid).doc(keys.deviceId).get();
      // Existing local keys are not proof that this device is still registered.
      // A missing record can be an interrupted install or a removed device; do
      // not republish it implicitly or advertise readiness.
      if (!mine.exists) throw NeedsRecoveryException();
      if (mine.data()?['revokedAt'] != null) {
        throw DeviceRevokedException();
      }
      final published = mine.data()!;
      if (bundle.toFirestore().entries.any(
        (entry) => published[entry.key] != entry.value,
      )) {
        throw NeedsRecoveryException();
      }
      _localIdentity = identity;
      return LocalDevice(identity, keys, bundle);
    }
    if (idJson != null || devJson != null || bundleJson != null) {
      throw StateError('Corrupt local key storage; refusing to overwrite.');
    }
    final existing = await _devices(uid).limit(1).get();
    if (existing.docs.isNotEmpty) throw NeedsRecoveryException();

    return installDevice(
      uid,
      await AccountIdentity.generate(),
      await DeviceKeys.generate(),
    );
  }

  /// Certifies [keys] with [identity], stores everything locally, then publishes
  /// the device. Used for first run, recovery and linking.
  Future<LocalDevice> installDevice(
    String uid,
    AccountIdentity identity,
    DeviceKeys keys,
  ) async {
    _bindAccount(uid);
    final bundle = await keys.certify(identity, uid);
    // Persist locally BEFORE publishing so a crash can't orphan a published device.
    await _store.write('identity:$uid', jsonEncode(identity.toJson()));
    await _store.write('device:$uid', jsonEncode(keys.toJson()));
    await _store.write('bundle:$uid', jsonEncode(bundle.toFirestore()));
    await _devices(uid).doc(keys.deviceId).set({
      ...bundle.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    _localIdentity = identity;
    return LocalDevice(identity, keys, bundle);
  }

  /// Active (non-revoked, correctly certified) devices of [uid], with TOFU identity pinning.
  Future<List<DeviceBundle>> fetchDevices(String uid) async {
    final snap = await _devices(uid).get();
    final out = <DeviceBundle>[];
    for (final d in snap.docs) {
      final b = await _bundleFrom(uid, d);
      if (b != null) out.add(b);
    }
    return out;
  }

  Future<DeviceBundle?> fetchDevice(String uid, String deviceId) async {
    final d = await _devices(uid).doc(deviceId).get();
    if (!d.exists) return null;
    return _bundleFrom(uid, d);
  }

  Future<DeviceBundle?> _bundleFrom(
    String uid,
    DocumentSnapshot<Map<String, dynamic>> d,
  ) async {
    final data = d.data()!;
    if (data['revokedAt'] != null) return null;
    final DeviceBundle b;
    try {
      b = DeviceBundle.fromFirestore(uid, d.id, data);
    } catch (_) {
      return null; // malformed document
    }
    if (!await b.verifyCert()) return null;
    await _checkPin(uid, b.identityPub);
    return b;
  }

  // ------------------------------------------------------------- identity pins

  Future<void> _checkPin(String peerUid, List<int> identityPub) async {
    final pinned = await _store.read(_trustKey('pin', peerUid));
    if (pinned == null) {
      await _store.write(
        _trustKey('pin', peerUid),
        b64(identityPub),
      ); // trust on first use
    } else if (!bytesEqual(unb64(pinned), identityPub)) {
      throw IdentityChangedException(peerUid, identityPub);
    }
  }

  Future<List<int>?> pinnedIdentity(String peerUid) async {
    final p = await _store.read(_trustKey('pin', peerUid));
    return p == null ? null : unb64(p);
  }

  /// The user explicitly accepted a changed identity (e.g. after re-verifying).
  Future<void> acceptIdentityChange(String peerUid, List<int> identityPub) =>
      _store.write(_trustKey('pin', peerUid), b64(identityPub));

  // ------------------------------------------------------------ verification

  /// True only if the user verified exactly the identity we currently trust.
  Future<bool> isVerified(String peerUid) async {
    final v = await _store.read(_trustKey('verified', peerUid));
    final pin = await pinnedIdentity(peerUid);
    if (v == null || pin == null) return false;
    try {
      final record = jsonDecode(v) as Map<String, dynamic>;
      return bytesEqual(unb64(record['peer'] as String), pin) &&
          bytesEqual(
            unb64(record['local'] as String),
            _localIdentity!.publicBytes,
          );
    } catch (_) {
      return false;
    }
  }

  /// Records that the user compared the safety number for [identityPub].
  Future<void> markVerified(String peerUid, List<int> identityPub) =>
      _store.write(
        _trustKey('verified', peerUid),
        jsonEncode({
          'peer': b64(identityPub),
          'local': b64(_localIdentity!.publicBytes),
        }),
      );

  Future<void> clearVerified(String peerUid) =>
      _store.delete(_trustKey('verified', peerUid));

  // ------------------------------------------------------------- new devices

  /// Device ids of [peerUid] not seen before. The first call only records the
  /// current devices (trust on first use) and returns nothing.
  Future<List<String>> detectNewDevices(String peerUid) async {
    final ids = (await fetchDevices(peerUid)).map((d) => d.deviceId).toSet();
    final raw = await _store.read(_trustKey('known', peerUid));
    final known = raw == null
        ? null
        : (jsonDecode(raw) as List).cast<String>().toSet();
    await _store.write(
      _trustKey('known', peerUid),
      jsonEncode((known ?? {}).union(ids).toList()),
    );
    if (known == null) return [];
    return ids.difference(known).toList()..sort();
  }

  // ------------------------------------------------------------- own devices

  Future<List<DeviceInfo>> listOwnDevices(
    String uid,
    String thisDeviceId,
  ) async {
    final snap = await _devices(uid).get();
    final out =
        [
          for (final d in snap.docs)
            DeviceInfo(
              d.id,
              (d.data()['createdAt'] as Timestamp?)?.toDate(),
              d.data()['revokedAt'] != null,
              d.id == thisDeviceId,
            ),
        ]..sort(
          (a, b) => (a.createdAt ?? DateTime(0)).compareTo(
            b.createdAt ?? DateTime(0),
          ),
        );
    return out;
  }

  /// Revokes another device: peers stop encrypting to it. (The current device
  /// can't be revoked here; sign out instead.)
  Future<void> revokeDevice(
    String uid,
    String deviceId, {
    required String thisDeviceId,
  }) async {
    if (deviceId == thisDeviceId) {
      throw StateError('Cannot revoke the current device.');
    }
    await _devices(uid)
        .doc(deviceId)
        .update({'revokedAt': FieldValue.serverTimestamp()});
  }
}

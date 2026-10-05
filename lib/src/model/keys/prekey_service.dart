import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fireplace/src/crypto/device.dart';
import 'package:fireplace/src/crypto/prekeys.dart';
import 'package:fireplace/src/crypto/session.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/db/secret_store.dart';

class PreKeyException implements Exception {
  PreKeyException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Publishes and rotates this device's prekeys, and claims prekeys of peers.
///
/// - One **signed prekey** (certified by the account identity), rotated weekly.
///   The previous one's private half is kept for [signedRetention] so handshakes
///   already in flight still complete, then deleted.
/// - A pool of **one-time prekeys**. Each is deleted (privately and on the
///   server) as soon as a session has been established with it.
///
/// Deleting private prekeys is what gives sessions forward secrecy.
class PreKeyService {
  PreKeyService(this._db, this._store, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final SecretStore _store;
  final DateTime Function() _now;

  static const signedLifetime = Duration(days: 7);
  static const signedRetention = Duration(days: 14);

  /// A claimed prekey whose handshake never arrives keeps its private half until here.
  static const oneTimeRetention = Duration(days: 30);
  static const poolTarget = 20;
  static const poolLowWater = 10;
  static const _claimFetch = 10;

  CollectionReference<Map<String, dynamic>> _col(String uid, String deviceId) =>
      _db
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(deviceId)
          .collection('prekeys');

  String _key(String uid, String deviceId) => 'prekeys:$uid:$deviceId';

  Future<_Secrets> _load(String uid, String deviceId) async {
    final raw = await _store.read(_key(uid, deviceId));
    if (raw == null) return _Secrets();
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return _Secrets(); // unreadable: start over (public orphans are cleaned up by maintain)
    }
    final parsed = _Secrets.fromJson(
      j,
    ); // skips records that fail strict parsing
    // keep only records whose public and private halves belong together
    final good = _Secrets();
    for (final r in parsed.signed) {
      if (await r.consistent()) good.signed.add(r);
    }
    for (final e in parsed.oneTime.entries) {
      if (e.key == e.value.id && await e.value.consistent()) {
        good.oneTime[e.key] = e.value;
      }
    }
    return good;
  }

  Future<void> _save(String uid, String deviceId, _Secrets s) =>
      _store.write(_key(uid, deviceId), jsonEncode(s.toJson()));

  // ---------------------------------------------------------------- publishing

  /// Call on every app start: rotates the signed prekey if due and tops up the
  /// one-time pool. Cheap when nothing is needed (one query for the pool size).
  Future<void> maintain(String uid, LocalDevice dev) async {
    final deviceId = dev.keys.deviceId;
    final s = await _load(uid, deviceId);
    final now = _now();

    // --- signed prekey
    final cur = s.signed.isEmpty ? null : s.signed.last;
    if (cur == null || now.difference(cur.createdAt) >= signedLifetime) {
      final rec = await PreKeyRecord.generate(now: now);
      final pub = await PreKeys.sign(rec, dev.identity, uid, deviceId);
      s.signed.add(rec);
      await _save(uid, deviceId, s); // keep the private half BEFORE publishing
      await _col(uid, deviceId).doc(rec.id).set({
        ...pub.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (cur != null) {
        // the superseded one disappears from the server at once
        await _col(uid, deviceId).doc(cur.id).delete();
      }
    }
    // retire old private halves
    final before = s.signed.length;
    s.signed.removeWhere(
      (r) =>
          r != s.signed.last && now.difference(r.createdAt) > signedRetention,
    );

    // --- one-time pool
    final col = _col(uid, deviceId);
    var have =
        (await col.where('kind', isEqualTo: 'onetime').count().get()).count ??
        0;
    // More published than we hold private halves for means some published keys can
    // never be used (lost or restored device state). Remove those orphans, otherwise
    // peers would keep picking prekeys we cannot answer.
    if (have > s.oneTime.length) {
      for (final d
          in (await col.where('kind', isEqualTo: 'onetime').get()).docs) {
        if (!s.oneTime.containsKey(d.id)) {
          await d.reference.delete();
          have--;
        }
      }
    }
    // Private halves whose public document is long gone were claimed by someone who
    // never completed a session: forget them instead of keeping the key forever.
    final cutoff = now.subtract(oneTimeRetention);
    final stale = s.oneTime.values
        .where((r) => r.createdAt.isBefore(cutoff))
        .toList();
    if (stale.isNotEmpty) {
      final published = (await col.where('kind', isEqualTo: 'onetime').get())
          .docs
          .map((d) => d.id)
          .toSet();
      for (final r in stale) {
        if (!published.contains(r.id)) s.oneTime.remove(r.id);
      }
    }
    if (have < poolLowWater) {
      for (var i = 0; i < poolTarget - have; i++) {
        final rec = await PreKeyRecord.generate(now: now);
        s.oneTime[rec.id] = rec;
        await _save(uid, deviceId, s);
        await _col(uid, deviceId).doc(rec.id).set({
          ...PreKeys.oneTime(rec).toFirestore(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } else if (s.signed.length != before) {
      await _save(uid, deviceId, s);
    }
    await _save(uid, deviceId, s);
  }

  // ------------------------------------------------------------------ claiming

  /// Fetches a verified signed prekey and (if available) a random one-time
  /// prekey of [target]. Forged or malformed prekeys are ignored.
  Future<PreKeyBundle> fetchBundle(DeviceBundle target) async {
    final col = _col(target.uid, target.deviceId);
    PublishedPreKey? best;
    DateTime bestAt = DateTime.fromMillisecondsSinceEpoch(0);
    for (final d in (await col.where('kind', isEqualTo: 'signed').get()).docs) {
      try {
        final p = PublishedPreKey.fromFirestore(d.id, d.data());
        if (!await PreKeys.verifySigned(target, p)) continue;
        final at = (d.data()['createdAt'] as Timestamp?)?.toDate() ?? bestAt;
        if (best == null || at.isAfter(bestAt)) {
          best = p;
          bestAt = at;
        }
      } on FormatException {
        continue;
      }
    }
    if (best == null) {
      throw PreKeyException(
        'This contact has not published encryption keys yet. Ask them to '
        'open Fireplace once.',
      );
    }
    // Claim a one-time prekey ATOMICALLY: a transaction reads it and deletes the
    // public document, so two people starting a session at the same moment can
    // never end up with the same one. If every candidate is taken or the pool is
    // empty, the session simply uses the signed prekey alone.
    final candidates =
        (await col.where('kind', isEqualTo: 'onetime').limit(_claimFetch).get())
            .docs
            .toList()
          ..shuffle(Random.secure());
    PublishedPreKey? claimed;
    for (final c in candidates) {
      try {
        claimed = await _db.runTransaction<PublishedPreKey?>((tx) async {
          final snap = await tx.get(c.reference);
          if (!snap.exists) return null; // somebody else took it
          final key = PublishedPreKey.fromFirestore(snap.id, snap.data()!);
          tx.delete(c.reference);
          return key;
        });
      } on FormatException {
        continue; // malformed document: skip it
      } on FirebaseException {
        continue; // lost a race or rules refused: try another
      }
      if (claimed != null) break;
    }
    return PreKeyBundle(device: target, signed: best, oneTime: claimed);
  }

  // ----------------------------------------------------------------- responding

  /// Looks up the local private prekeys named by an incoming handshake.
  /// Returns null if the signed prekey is unknown or the one-time prekey was
  /// already used.
  Future<({PreKeyRecord signed, PreKeyRecord? oneTime})?> resolve(
    String uid,
    String deviceId,
    HandshakeInit hs,
  ) async {
    final s = await _load(uid, deviceId);
    PreKeyRecord? spk;
    for (final r in s.signed) {
      if (r.id == hs.spkId) spk = r;
    }
    if (spk == null) return null;
    PreKeyRecord? opk;
    if (hs.opkId != null) {
      opk = s.oneTime[hs.opkId];
      if (opk == null) return null;
    }
    return (signed: spk, oneTime: opk);
  }

  /// Deletes a used one-time prekey (private half first, then the public doc).
  Future<void> consumeOneTime(String uid, String deviceId, String opkId) async {
    final s = await _load(uid, deviceId);
    if (s.oneTime.remove(opkId) != null) await _save(uid, deviceId, s);
    try {
      await _col(uid, deviceId).doc(opkId).delete();
    } catch (_) {
      // Best effort: a leftover public doc only means a peer may later pick an
      // already-consumed key, and that handshake will be refused.
    }
  }
}

class _Secrets {
  _Secrets();
  final List<PreKeyRecord> signed = [];
  final Map<String, PreKeyRecord> oneTime = {};

  factory _Secrets.fromJson(Map<String, dynamic> j) {
    final s = _Secrets();
    final signed = j['signed'], oneTime = j['oneTime'];
    if (signed is List) {
      for (final r in signed) {
        try {
          s.signed.add(PreKeyRecord.fromJson(Map<String, dynamic>.from(r)));
        } catch (_) {
          // a damaged record can never work: skip it
        }
      }
    }
    if (oneTime is Map) {
      oneTime.forEach((k, v) {
        try {
          s.oneTime['$k'] = PreKeyRecord.fromJson(Map<String, dynamic>.from(v));
        } catch (_) {}
      });
    }
    return s;
  }

  Map<String, dynamic> toJson() => {
    'signed': [for (final r in signed) r.toJson()],
    'oneTime': oneTime.map((k, v) => MapEntry(k, v.toJson())),
  };
}

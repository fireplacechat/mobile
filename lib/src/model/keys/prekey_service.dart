import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fireplace/src/crypto/device.dart';
import 'package:fireplace/src/crypto/prekeys.dart';
import 'package:fireplace/src/crypto/session.dart';
import 'package:fireplace/src/model/common/async_mutex.dart';
import 'package:fireplace/src/model/common/daily_counter.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/shared_lock.dart';

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
  PreKeyService(
    this._db,
    this._store, {
    DateTime Function()? clock,
    SharedLock? lock,
  }) : _now = clock ?? DateTime.now,
       _lock = lock ?? SharedLock();

  final FirebaseFirestore _db;
  final SecretStore _store;

  /// The account lock: a background isolate may consume a one-time prekey
  /// while the app refills the pool (decision 0030).
  final SharedLock _lock;
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
  ///
  /// Safe to run in the background while messages are received: every change
  /// to the private prekeys is one load, change and save under [_state], never
  /// held across a network call, so a one-time prekey consumed meanwhile stays
  /// consumed. Two calls at once share one run. [isStopped] ends the run early
  /// (the session closed) before it writes anything more.
  Future<void> maintain(
    String uid,
    LocalDevice dev, {
    bool Function()? isStopped,
  }) => _maintaining ??= _maintain(
    uid,
    dev,
    isStopped ?? () => false,
  ).whenComplete(() => _maintaining = null);

  Future<void>? _maintaining;
  final _state = AsyncMutex();

  /// Loads the private prekeys, applies [change] and saves them if it returns
  /// true, all under the account lock and then [_state]. Always in that
  /// order: a receive holds the account lock when it consumes a prekey.
  Future<void> _update(
    String uid,
    String deviceId,
    bool Function(_Secrets s) change,
  ) => _lock.run(
    () => _state.run(() async {
      final s = await _load(uid, deviceId);
      if (change(s)) await _save(uid, deviceId, s);
    }),
  );

  /// True once this device holds a signed prekey, which upkeep publishes as
  /// it makes it. False on a new device: nobody can start a conversation with
  /// it until upkeep has run once.
  Future<bool> hasSignedPreKey(String uid, String deviceId) async =>
      (await _load(uid, deviceId)).signed.isNotEmpty;

  Future<void> _maintain(
    String uid,
    LocalDevice dev,
    bool Function() isStopped,
  ) async {
    final deviceId = dev.keys.deviceId;
    final now = _now();

    // --- signed prekey
    final signed = (await _load(uid, deviceId)).signed;
    final cur = signed.isEmpty ? null : signed.last;
    if (cur == null || now.difference(cur.createdAt) >= signedLifetime) {
      final rec = await PreKeyRecord.generate(now: now);
      final pub = await PreKeys.sign(rec, dev.identity, uid, deviceId);
      if (isStopped()) return;
      // keep the private half BEFORE publishing
      await _update(uid, deviceId, (s) {
        s.signed.add(rec);
        return true;
      });
      await _col(uid, deviceId).doc(rec.id).set({
        ...pub.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (cur != null) {
        // the superseded one disappears from the server at once
        await _col(uid, deviceId).doc(cur.id).delete();
      }
    }
    if (isStopped()) return;
    // retire old private halves
    await _update(uid, deviceId, (s) {
      final before = s.signed.length;
      s.signed.removeWhere(
        (r) =>
            r != s.signed.last && now.difference(r.createdAt) > signedRetention,
      );
      return s.signed.length != before;
    });

    // --- one-time pool
    final col = _col(uid, deviceId);
    var have =
        (await col.where('kind', isEqualTo: 'onetime').count().get()).count ??
        0;
    final held = (await _load(uid, deviceId)).oneTime.keys.toSet();
    // More published than we hold private halves for means some published keys can
    // never be used (lost or restored device state). Remove those orphans, otherwise
    // peers would keep picking prekeys we cannot answer. (A key consumed meanwhile
    // has had its public document deleted already.)
    if (have > held.length) {
      for (final d
          in (await col.where('kind', isEqualTo: 'onetime').get()).docs) {
        if (!held.contains(d.id)) {
          await d.reference.delete();
          have--;
        }
      }
    }
    // Private halves whose public document is long gone were claimed by someone who
    // never completed a session: forget them instead of keeping the key forever.
    final cutoff = now.subtract(oneTimeRetention);
    final stale = (await _load(uid, deviceId)).oneTime.values
        .where((r) => r.createdAt.isBefore(cutoff))
        .map((r) => r.id)
        .toList();
    if (stale.isNotEmpty) {
      final published = (await col.where('kind', isEqualTo: 'onetime').get())
          .docs
          .map((d) => d.id)
          .toSet();
      if (isStopped()) return;
      await _update(uid, deviceId, (s) {
        var changed = false;
        for (final id in stale) {
          if (!published.contains(id)) changed |= s.oneTime.remove(id) != null;
        }
        return changed;
      });
    }
    if (have < poolLowWater) {
      for (var i = 0; i < poolTarget - have; i++) {
        final rec = await PreKeyRecord.generate(now: now);
        if (isStopped()) return;
        await _update(uid, deviceId, (s) {
          s.oneTime[rec.id] = rec;
          return true;
        });
        await _col(uid, deviceId).doc(rec.id).set({
          ...PreKeys.oneTime(rec).toFirestore(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }
    if (isStopped()) return;
    // Saving once more drops any damaged records the loads skipped.
    await _update(uid, deviceId, (_) => true);
  }

  // ------------------------------------------------------------------ claiming

  /// One-time prekeys this account claimed per day (backend decision 0017:
  /// at most 200), by claiming account.
  final _claims = <String, DailyCounter>{};

  /// Fetches a verified signed prekey and (if available) a random one-time
  /// prekey of [target]. Forged or malformed prekeys are ignored.
  ///
  /// The app passes [claimer], its own account: each claim is counted, and
  /// once the day's claims are used up the session simply uses the signed
  /// prekey alone, so a pool cannot be drained. Without it nothing is counted
  /// (tests and tools; the rules refuse that once an account has counted).
  Future<PreKeyBundle> fetchBundle(
    DeviceBundle target, {
    String? claimer,
  }) async {
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
    final counter = claimer == null
        ? null
        : _claims[claimer] ??= DailyCounter(_db, claimer, 'claims');
    PublishedPreKey? claimed;
    for (final c in candidates) {
      Future<PublishedPreKey?> claim(void Function(CounterWrite)? count) =>
          _db.runTransaction<PublishedPreKey?>((tx) async {
            final snap = await tx.get(c.reference);
            if (!snap.exists) return null; // somebody else took it
            final key = PublishedPreKey.fromFirestore(snap.id, snap.data()!);
            tx.delete(c.reference);
            count?.call(CounterWrite.transaction(tx));
            return key;
          });
      try {
        claimed = counter == null
            ? await claim(null)
            : await counter.withCount(claim);
      } on FormatException {
        continue; // malformed document: skip it
      } on FirebaseException catch (e) {
        // Refused in both counter forms: this account's claims for the day
        // are used up. The signed prekey alone still starts the session.
        if (counter != null && e.code == 'permission-denied') break;
        continue; // lost a race: try another
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
    await _update(uid, deviceId, (s) => s.oneTime.remove(opkId) != null);
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

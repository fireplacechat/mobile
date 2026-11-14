import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/model/common/daily_counter.dart';
import 'package:fireplace/src/model/groups/group_models.dart';

/// Membership requests (decision 0050): a document the server's
/// function completes with `status: done | refused`. Each is counted in
/// `limits/groupOps` in the same batch, as the rules require.
class GroupRequests {
  GroupRequests(this._db, this.uid, {Duration? timeout})
    : _timeout = timeout ?? const Duration(seconds: 30),
      _counter = DailyCounter(_db, uid, 'groupOps');

  final FirebaseFirestore _db;
  final String uid;
  final Duration _timeout;
  final DailyCounter _counter;

  static String newId() =>
      b64(randomBytes(12)).replaceAll('+', '-').replaceAll('/', '_');

  /// An account-level request: create, accept or decline.
  Future<void> account(String kind, Map<String, Object> fields) =>
      _run(_db.doc('users/$uid/groupOps/${newId()}'), kind, fields);

  /// A request about one group: invite, add, addDevice, remove, leave,
  /// finalize or roles.
  Future<void> group(String gid, String kind, Map<String, Object> fields) =>
      _run(_db.doc('groups/$gid/ops/${newId()}'), kind, fields);

  /// Writes the request and waits for the server's answer. Throws
  /// [GroupRefused] with the server's reason, or [TimeoutException] when the
  /// outcome is not known yet (the request may still be handled).
  Future<void> _run(
    DocumentReference<Map<String, dynamic>> ref,
    String kind,
    Map<String, Object> fields,
  ) async {
    await _counter.withCount((add) async {
      final batch = _db.batch()
        ..set(ref, {
          'kind': kind,
          'by': uid,
          'at': FieldValue.serverTimestamp(),
          ...fields,
        });
      add(CounterWrite.batch(batch));
      await batch.commit();
    });
    final done = Completer<void>();
    var seen = false;
    final sub = ref.snapshots().listen(
      (snap) {
        // The last member leaving deletes the group with its requests: done.
        if (!snap.exists && seen && !done.isCompleted) done.complete();
        if (snap.exists) seen = true;
        final status = snap.data()?['status'];
        if (status == 'done' && !done.isCompleted) done.complete();
        if (status == 'refused' && !done.isCompleted) {
          done.completeError(
            GroupRefused('${snap.data()?['reason'] ?? 'refused'}'),
          );
        }
      },
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      },
    );
    try {
      await done.future.timeout(_timeout);
    } finally {
      await sub.cancel();
    }
  }
}

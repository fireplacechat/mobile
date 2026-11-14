import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fireplace/src/model/account/auth_service.dart';
import 'package:fireplace/src/model/invites/invite_rows.dart';

class InviteException implements Exception {
  InviteException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads and writes this account's invite rows (backend decision 0021).
///
/// The rules decide everything: when a row unlocks, whether invites are
/// paused, and that a code matches its hash. This class only mirrors them so
/// the page can show the right state.
class InviteService {
  InviteService(this._db, {Random? random, this.commitTimeout = _timeout})
    : _random = random ?? Random.secure();

  final FirebaseFirestore _db;
  final Random _random;
  final Duration commitTimeout;
  static const _timeout = Duration(seconds: 20);

  DocumentReference<Map<String, dynamic>> _slot(String uid, int row) =>
      _db.doc('users/$uid/inviteSlots/$row');

  /// The account's invites, live: the operator's schedule, the account's own
  /// allowance and its rows. Listeners run only while the page is open.
  Stream<InviteState> watch(String uid) {
    late final StreamController<InviteState> out;
    final subs = <StreamSubscription<Object?>>[];
    DateTime? createdAt;
    Map<String, dynamic>? config, allowance;
    var haveConfig = false, haveAllowance = false;
    Map<int, InviteSlot>? slots;

    void emit() {
      if (createdAt == null || !haveConfig || !haveAllowance || slots == null) {
        return;
      }
      final own = allowance;
      final schedule = own ?? config ?? const <String, dynamic>{};
      out.add(
        InviteState(
          createdAt: createdAt!,
          unlockAfter: _unlocks(schedule['unlockAfter']),
          paused: config?['paused'] == true || own?['paused'] == true,
          slots: slots!,
        ),
      );
    }

    void fail(Object e, StackTrace s) {
      if (!out.isClosed) out.addError(e, s);
    }

    out = StreamController<InviteState>(
      onListen: () {
        // createdAt never changes, so one read is enough.
        _db
            .doc('users/$uid')
            .get()
            .then((snap) {
              final at = snap.data()?['createdAt'];
              if (at is! Timestamp) {
                throw InviteException('Your account is not ready yet.');
              }
              createdAt = at.toDate();
              emit();
            })
            .catchError(fail);
        subs
          ..add(
            _db.doc('config/invites').snapshots().listen((snap) {
              config = snap.data();
              haveConfig = true;
              emit();
            }, onError: fail),
          )
          ..add(
            _db.doc('inviteAllowances/$uid').snapshots().listen((snap) {
              allowance = snap.data();
              haveAllowance = true;
              emit();
            }, onError: fail),
          )
          ..add(
            _db
                .collection('users/$uid/inviteSlots')
                .snapshots(includeMetadataChanges: true)
                .listen((snap) {
                  slots = {
                    for (final d in snap.docs) ?_row(d.id): ?_parseSlot(d),
                  };
                  emit();
                }, onError: fail),
          );
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return out.stream;
  }

  static int? _row(String id) {
    final n = int.tryParse(id);
    return n != null && n >= 0 && n < maxInviteRows && '$n' == id ? n : null;
  }

  static InviteSlot? _parseSlot(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final code = data?['code'], invite = data?['invite'];
    if (code is! String || invite is! String) return null;
    final replacedAt = data?['replacedAt'];
    return InviteSlot(
      code: code,
      invite: invite,
      used: data?['used'] == true,
      replacedAt: replacedAt is Timestamp ? replacedAt.toDate() : null,
      pending: d.metadata.hasPendingWrites,
    );
  }

  static List<Duration> _unlocks(Object? raw) {
    if (raw is! List || raw.isEmpty) {
      return raw is List ? const [] : defaultInviteUnlocks;
    }
    return [
      for (final s in raw.take(maxInviteRows))
        if (s is int && s >= 0) Duration(seconds: s) else Duration.zero,
    ];
  }

  /// Makes a code for [row]. The server refuses a row that has not unlocked.
  Future<void> create(String uid, int row) async {
    final code = newInviteCode(_random);
    final hash = await AuthService.inviteHash(code);
    final b = _db.batch()
      ..set(_slot(uid, row), {
        'code': code,
        'invite': hash,
        'at': FieldValue.serverTimestamp(),
      })
      ..set(_db.doc('invites/$hash'), {
        'by': uid,
        'slot': row,
        'createdAt': FieldValue.serverTimestamp(),
      });
    await _commit(b, refused: _refusedCreate);
  }

  /// Swaps the unused code in [row] for a new one; the old code stops working.
  Future<void> replace(String uid, int row, InviteSlot old) async {
    final code = newInviteCode(_random);
    final hash = await AuthService.inviteHash(code);
    final b = _db.batch()
      ..delete(_db.doc('invites/${old.invite}'))
      ..set(_slot(uid, row), {
        'code': code,
        'invite': hash,
        'at': FieldValue.serverTimestamp(),
        'replacedAt': FieldValue.serverTimestamp(),
      })
      ..set(_db.doc('invites/$hash'), {
        'by': uid,
        'slot': row,
        'createdAt': FieldValue.serverTimestamp(),
      });
    await _commit(b, refused: _refusedReplace);
  }

  static const _refusedCreate =
      'This invite is not ready yet, or invites are paused. If the countdown '
      'has ended, check that the date and time on your phone are right.';
  static const _refusedReplace =
      'This code cannot be replaced right now. It may have been used, or you '
      'replaced it less than an hour ago.';

  /// Never retried: a write that may have reached the server shows up in the
  /// rows if it did, and the person decides whether to try again.
  Future<void> _commit(WriteBatch b, {required String refused}) async {
    try {
      await b.commit().timeout(commitTimeout);
    } on TimeoutException {
      throw InviteException(
        'Not confirmed yet. If the code appears here, it was saved.',
      );
    } on FirebaseException catch (e) {
      throw InviteException(
        e.code == 'permission-denied'
            ? refused
            : 'Could not reach Fireplace. Check your connection and try again.',
      );
    }
  }
}

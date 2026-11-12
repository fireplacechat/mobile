import 'package:cloud_firestore/cloud_firestore.dart';

/// A per-account daily counter the rules check (backend decision 0017): the
/// document `users/{uid}/limits/{name}` is written in the same batch or
/// transaction as the action it counts, so counting needs no read. The rules
/// cap it per day of 24 hours from the first action (50 new chats, 200
/// one-time prekey claims).
///
/// Two forms, as for the send clock (decision 0028): counting in the running
/// day, `update({at, today: +1})`, or opening a new day, `set({at, day,
/// today: 1})`. This remembers which applies from its own last success; when
/// it does not know, or guesses wrong, the server refuses and the other form
/// is tried ([withCount]).
class DailyCounter {
  DailyCounter(this._db, this.uid, this.name, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final String uid, name;
  final DateTime Function() _now;

  static const day = Duration(days: 1);
  static const _margin = Duration(minutes: 1);

  DateTime? _dayOpened;

  DocumentReference<Map<String, dynamic>> get _ref =>
      _db.collection('users').doc(uid).collection('limits').doc(name);

  /// Whether the next action probably opens a new day.
  bool get _opensDay {
    final opened = _dayOpened;
    return opened == null || _now().difference(opened) >= day - _margin;
  }

  /// Runs [action], which must add the counter with the `add` callback it is
  /// given (to its batch or transaction). Tries the likelier form first and
  /// the other one if the server refuses. If both are refused, the last
  /// refusal is rethrown (the cap, or a refusal of the action itself). The
  /// rules refuse an action without its counter (backend #21), so there is
  /// no attempt without one.
  Future<T> withCount<T>(
    Future<T> Function(void Function(CounterWrite write) add) action,
  ) async {
    final first = _opensDay;
    for (final opensDay in [first, !first]) {
      final startedAt = _now();
      try {
        void add(CounterWrite write) {
          if (opensDay) {
            write.set(_ref, {
              'at': FieldValue.serverTimestamp(),
              'day': FieldValue.serverTimestamp(),
              'today': 1,
            });
          } else {
            write.update(_ref, {
              'at': FieldValue.serverTimestamp(),
              'today': FieldValue.increment(1),
            });
          }
        }

        final result = await action(add);
        if (opensDay) {
          _dayOpened = startedAt;
        } else {
          // A day another device opened runs; when it began is unknown, so
          // assume now and let the server correct a wrong guess.
          _dayOpened ??= startedAt;
        }
        return result;
      } on FirebaseException catch (e) {
        final refused = e.code == 'permission-denied' || e.code == 'not-found';
        if (!refused || opensDay != first) rethrow;
      }
    }
    throw StateError('unreachable');
  }
}

/// The two places a counter can be written: a batch or a transaction.
class CounterWrite {
  CounterWrite.batch(WriteBatch this._batch) : _tx = null;
  CounterWrite.transaction(Transaction this._tx) : _batch = null;
  final WriteBatch? _batch;
  final Transaction? _tx;

  void set(DocumentReference<Map<String, dynamic>> ref, Map<String, Object> d) {
    _batch?.set(ref, d);
    _tx?.set(ref, d);
  }

  void update(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, Object> d,
  ) {
    _batch?.update(ref, d);
    _tx?.update(ref, d);
  }
}

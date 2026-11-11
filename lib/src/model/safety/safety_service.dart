import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fireplace/src/db/secret_store.dart';

/// Blocking, spam reports and locally hiding message requests.
///
/// - **Block**: a document in `users/{me}/blocks/{peer}`. The Firestore rules refuse
///   chat creation and messages from a blocked person, and this device ignores
///   anything of theirs that is still in flight.
/// - **Report spam**: a write-only document in `reports/{me}_{peer}` for the
///   operator. It names the two accounts and nothing else. Message text is never
///   copied into it.
/// - **Hide**: a purely local "ignore" for message requests.
class SafetyService {
  SafetyService(this._db, this._store, this.uid);
  final FirebaseFirestore _db;
  final SecretStore _store;
  final String uid;

  Set<String> _blocked = {};
  Set<String>? _hidden;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  final _blockedCtrl = StreamController<Set<String>>.broadcast();

  CollectionReference<Map<String, dynamic>> get _blocks =>
      _db.collection('users').doc(uid).collection('blocks');

  /// Loads the block list and keeps it current. Call once after sign-in.
  Future<void> start() async {
    _blocked = (await _blocks.get()).docs.map((d) => d.id).toSet();
    _blockedCtrl.add(_blocked);
    _sub = _blocks.snapshots().listen((s) {
      _blocked = s.docs.map((d) => d.id).toSet();
      _blockedCtrl.add(_blocked);
    }, onError: (_) {});
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _blockedCtrl.close();
  }

  bool isBlocked(String peerUid) => _blocked.contains(peerUid);
  Set<String> get blocked => Set.unmodifiable(_blocked);
  Stream<Set<String>> watchBlocked() => Stream.multi((sink) {
    // Keep block changes observed while the initial snapshot is delivered/paused.
    final sub = _blockedCtrl.stream.listen(
      sink.add,
      onError: sink.addError,
      onDone: sink.close,
    );
    sink.onCancel = sub.cancel;
    sink.add(blocked);
  });

  Future<void> block(String peerUid) async {
    await _blocks.doc(peerUid).set({'createdAt': FieldValue.serverTimestamp()});
    _blocked = {..._blocked, peerUid};
    _blockedCtrl.add(_blocked);
  }

  Future<void> unblock(String peerUid) async {
    await _blocks.doc(peerUid).delete();
    _blocked = {..._blocked}..remove(peerUid);
    _blockedCtrl.add(_blocked);
  }

  /// Tells the operator that [peerUid] may be sending spam.
  ///
  /// The document is only the two account ids, the reason and the time. There
  /// is no field for message text, and this method cannot add one.
  Future<void> reportSpam(String peerUid) async {
    await _db.collection('reports').doc('${uid}_$peerUid').set({
      'reporter': uid,
      'reported': peerUid,
      'reason': 'spam',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ------------------------------------------------------------ hidden requests

  String get _hiddenKey => 'hidden:$uid';

  Future<Set<String>> hiddenChats() async {
    if (_hidden != null) return _hidden!;
    final raw = await _store.read(_hiddenKey);
    return _hidden = raw == null
        ? <String>{}
        : (jsonDecode(raw) as List).cast<String>().toSet();
  }

  Future<void> hideChat(String chatId) async {
    final h = {...await hiddenChats(), chatId};
    _hidden = h;
    await _store.write(_hiddenKey, jsonEncode(h.toList()));
  }

  Future<void> unhideChat(String chatId) async {
    final h = {...await hiddenChats()}..remove(chatId);
    _hidden = h;
    await _store.write(_hiddenKey, jsonEncode(h.toList()));
  }
}

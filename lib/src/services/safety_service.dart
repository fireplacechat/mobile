import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'secret_store.dart';

enum ReportReason { spam, harassment, abuse, impersonation, other }

/// Blocking, reporting and locally hiding message requests.
///
/// - **Block**: a document in `users/{me}/blocks/{peer}`. The Firestore rules refuse
///   chat creation and messages from a blocked person, and this device ignores
///   anything of theirs that is still in flight.
/// - **Report**: a write-only document in `reports/` for the app operator. The
///   messages are end-to-end encrypted, so context is only what the reporter
///   chooses to include, and it cannot be verified.
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

  /// [context] is optional plaintext the reporter chooses to share (max 20 lines).
  Future<void> report({
    required String peerUid,
    required ReportReason reason,
    String? chatId,
    String? note,
    List<String> context = const [],
  }) async {
    final trimmed = (note ?? '').trim();
    await _db.collection('reports').doc('${uid}_$peerUid').set({
      'reporter': uid,
      'reported': peerUid,
      'reason': reason.name,
      'chatId': ?chatId,
      if (trimmed.isNotEmpty)
        'note': trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed,
      if (context.isNotEmpty)
        'context': [
          for (final c in context.take(20))
            c.length > 1000 ? c.substring(0, 1000) : c,
        ],
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

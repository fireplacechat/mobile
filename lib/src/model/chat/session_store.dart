import 'dart:convert';

import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/src/db/secret_store.dart';

/// Sessions advanced by encrypting one message for one device.
typedef AdvancedSessions = ({
  String uid,
  String deviceId,
  List<Session> sessions,
});

/// What [SessionStore.saveAhead] replaced, to put back with
/// [SessionStore.restoreSessions].
typedef SessionUndo = List<(String uid, String deviceId, String? stored)>;

/// This device's ratchet sessions with each peer device, in [SecretStore].
/// [saveAhead] stores them before a message is published; see there for why.
class SessionStore {
  SessionStore(this._secrets, this.device);

  final SecretStore _secrets;
  final LocalDevice device;

  String sessKey(String peerUid, String peerDev) =>
      'sess:${device.keys.deviceId}:$peerUid:$peerDev';

  Future<List<Session>> loadSessions(String peerUid, String peerDev) async {
    final raw = await _secrets.read(sessKey(peerUid, peerDev));
    if (raw == null) return [];
    final out = <Session>[];
    for (final j in jsonDecode(raw) as List) {
      // Sessions from an older protocol version are dropped; a fresh handshake
      // replaces them.
      final sess = Session.tryFromJson(Map<String, dynamic>.from(j));
      // also drop sessions whose stored key pairs no longer match each other
      if (sess != null && await sess.selfCheck()) out.add(sess);
    }
    return out;
  }

  Future<void> saveSessions(String peerUid, String peerDev, List<Session> s) =>
      _secrets.write(
        sessKey(peerUid, peerDev),
        jsonEncode([for (final x in s) x.toJson()]),
      );

  /// The session to send on: one the peer has proven it holds (smallest id, so both
  /// sides converge), otherwise the newest one we started.
  static Session? pickSession(List<Session> sessions) {
    final usable = sessions.where((s) => s.canSend).toList();
    if (usable.isEmpty) return null;
    final acked = usable.where((s) => s.acknowledged).toList();
    if (acked.isNotEmpty) {
      return acked.reduce(
        (a, b) => a.sessionId.compareTo(b.sessionId) <= 0 ? a : b,
      );
    }
    usable.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return usable.first;
  }

  /// Saves [advanced] BEFORE its message is published (write-ahead). If the
  /// publish came first and this save then failed, the next message would be
  /// encrypted at a reused counter under the same key; saving first can at
  /// worst leave a gap in the counter, which receivers tolerate. Returns what
  /// to put back if the publish definitely fails. If this save fails, what it
  /// saved is put back already and nothing may be published.
  Future<SessionUndo> saveAhead(List<AdvancedSessions> advanced) async {
    final SessionUndo undo = [];
    try {
      for (final a in advanced) {
        undo.add((
          a.uid,
          a.deviceId,
          await _secrets.read(sessKey(a.uid, a.deviceId)),
        ));
        await saveSessions(a.uid, a.deviceId, a.sessions);
      }
    } catch (_) {
      await restoreSessions(undo);
      rethrow;
    }
    return undo;
  }

  Future<void> restoreSessions(SessionUndo undo) async {
    for (final (u, d, raw) in undo) {
      try {
        raw == null
            ? await _secrets.delete(sessKey(u, d))
            : await _secrets.write(sessKey(u, d), raw);
      } catch (_) {
        // Best effort: a failed restore only leaves a counter gap, never a reuse.
      }
    }
  }
}

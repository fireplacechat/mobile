import 'dart:convert';

import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/crypto/session.dart';
import 'package:fireplace/src/db/secret_store.dart';

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

  Future<void> restoreSessions(List<(String, String, String?)> undo) async {
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

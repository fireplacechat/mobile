import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fireplace/src/db/secret_store.dart';

/// Per chat, the time of the newest message this device has finished
/// receiving, kept in the secure store. A recovery watermark: it never passes
/// a message that is not finished, and it only moves forward.
class ReceiveCursor {
  ReceiveCursor(this._secrets, this._deviceId);

  final SecretStore _secrets;
  final String _deviceId;

  String _key(String chatId) => 'cursor:$_deviceId:$chatId';

  Future<Timestamp?> read(String chatId) async {
    final raw = await _secrets.read(_key(chatId));
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final sec = int.tryParse(parts[0]), ns = int.tryParse(parts[1]);
    return sec == null || ns == null ? null : Timestamp(sec, ns);
  }

  /// Call under the account lock: another isolate moves it too.
  Future<void> advance(String chatId, Timestamp to) async {
    final cur = await read(chatId);
    if (cur != null && cur.compareTo(to) >= 0) return;
    await _secrets.write(_key(chatId), '${to.seconds}:${to.nanoseconds}');
  }
}

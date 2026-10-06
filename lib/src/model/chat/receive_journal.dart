import 'dart:convert';

import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/model/keys/prekey_service.dart';
import 'package:fireplace/src/model/chat/session_store.dart';

class ReceiveJournal {
  ReceiveJournal(
    this._secrets,
    this._messages,
    this._prekeys,
    this._sess,
    this.uid,
    this.device,
  );

  final SecretStore _secrets;
  final LocalMessageStore _messages;
  final PreKeyService _prekeys;
  final SessionStore _sess;
  final String uid;
  final LocalDevice device;

  // ---- receive journal ------------------------------------------------------
  // After a message authenticates, its effects (history entry, advanced session,
  // spent one-time prekey) must all happen even if the app dies half way. The result
  // is first written as ONE journal record; applying it is idempotent and is
  // replayed before any other message is processed.

  String get _journalIndexKey => 'journals:${device.keys.deviceId}';
  String _journalKey(String chatId, String msgId) =>
      'journal:${device.keys.deviceId}:$chatId:$msgId';

  Future<List<String>> _journalIndex() async {
    final raw = await _secrets.read(_journalIndexKey);
    return raw == null ? [] : (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> writeJournal(Map<String, dynamic> j) async {
    final key = _journalKey(j['chatId'] as String, j['msgId'] as String);
    await _secrets.write(key, jsonEncode(j));
    final idx = await _journalIndex();
    if (!idx.contains(key)) {
      await _secrets.write(_journalIndexKey, jsonEncode([...idx, key]));
    }
  }

  Future<void> applyJournal(Map<String, dynamic> j) async {
    final chatId = j['chatId'] as String, msgId = j['msgId'] as String;
    if (!await _messages.has(chatId, msgId)) {
      await _messages.add(
        LocalMessage(
          id: msgId,
          chatId: chatId,
          senderUid: j['senderUid'] as String,
          senderDevice: j['senderDevice'] as String,
          outgoing: false,
          sentAt: DateTime.fromMillisecondsSinceEpoch(j['sentAt'] as int),
          body: j['body'] as String,
          status: MessageStatus.values.byName(j['status'] as String),
        ),
      );
    }
    await _secrets.write(
      _sess.sessKey(j['senderUid'] as String, j['senderDevice'] as String),
      j['sessions'] as String,
    );
    final opk = j['opk'];
    if (opk is String) {
      await _prekeys.consumeOneTime(uid, device.keys.deviceId, opk);
    }
    final key = _journalKey(chatId, msgId);
    await _secrets.delete(key);
    final idx = await _journalIndex();
    await _secrets.write(
      _journalIndexKey,
      jsonEncode(idx.where((k) => k != key).toList()),
    );
  }

  /// Completes any message whose effects were only partly applied (call under the lock).
  Future<void> recoverJournals() async {
    for (final key in await _journalIndex()) {
      final raw = await _secrets.read(key);
      if (raw == null) {
        final idx = await _journalIndex();
        await _secrets.write(
          _journalIndexKey,
          jsonEncode(idx.where((k) => k != key).toList()),
        );
        continue;
      }
      await applyJournal(jsonDecode(raw) as Map<String, dynamic>);
    }
  }
}

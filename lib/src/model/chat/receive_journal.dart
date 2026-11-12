import 'package:fireplace/src/db/message_quote.dart';

import 'dart:convert';

import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/message_mutation.dart';
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
  //
  // At most one journal is ever open: every receive and send first finishes the
  // open one, and fails if it cannot. So it has one fixed slot. Older versions
  // kept one key per message plus an index; those are still finished first.

  String get _slotKey => 'journal:${device.keys.deviceId}';
  String get _legacyIndexKey => 'journals:${device.keys.deviceId}';

  Future<List<String>> _legacyIndex() async {
    final raw = await _secrets.read(_legacyIndexKey);
    return raw == null ? [] : (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> writeJournal(Map<String, dynamic> j) =>
      _secrets.write(_slotKey, jsonEncode(j));

  Future<void> applyJournal(Map<String, dynamic> j) =>
      _apply(j, () => _secrets.delete(_slotKey));

  Future<void> _apply(
    Map<String, dynamic> j,
    Future<void> Function() close,
  ) async {
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
          quote: j['quote'] == null
              ? null
              : MessageQuote.fromJson(Map<String, dynamic>.from(j['quote'])),
          status: MessageStatus.values.byName(j['status'] as String),
          mutation: j['mutation'] == null
              ? null
              : MessageMutation.fromJson(
                  Map<String, dynamic>.from(j['mutation']),
                ),
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
    await close();
  }

  /// Completes any message whose effects were only partly applied (call under the lock).
  Future<void> recoverJournals() async {
    for (final key in await _legacyIndex()) {
      final raw = await _secrets.read(key);
      if (raw != null) {
        await _apply(
          jsonDecode(raw) as Map<String, dynamic>,
          () => _secrets.delete(key),
        );
      }
      final rest = (await _legacyIndex()).where((k) => k != key).toList();
      rest.isEmpty
          ? await _secrets.delete(_legacyIndexKey)
          : await _secrets.write(_legacyIndexKey, jsonEncode(rest));
    }
    final raw = await _secrets.read(_slotKey);
    if (raw != null) {
      await applyJournal(jsonDecode(raw) as Map<String, dynamic>);
    }
  }
}

import 'package:fireplace/src/db/message_quote.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/model/chat/chat_exceptions.dart';

/// Resolves sends with an unknown outcome: asks the server, repairs local
/// history, and resends only when the user chooses to.
class SendRecovery {
  SendRecovery(
    this._db,
    this._messages,
    this.uid,
    this.device, {
    required this.sendText,
    required this.sendQuoted,
    required this.sendSaved,
    required this.peerOf,
  });

  final FirebaseFirestore _db;
  final LocalMessageStore _messages;
  final String uid;
  final LocalDevice device;
  final Future<void> Function(String chatId, String text) sendText;
  final String Function(String chatId) peerOf;
  final Future<void> Function(String, String, MessageQuote) sendQuoted;
  final Future<void> Function(LocalMessage saved) sendSaved;

  /// Asks the SERVER whether an unconfirmed message exists. Only server evidence counts: a
  /// missing document, an offline error or a cached answer never proves it was not published.
  /// Never publishes anything. When the server holds it, local history is repaired.
  Future<SendOutcome> checkSendStatus(String chatId, String messageId) async {
    if (await _onServer(chatId, messageId) != true) {
      return SendOutcome.publishUnknown;
    }
    try {
      await confirmOwnSend(chatId, messageId);
    } catch (_) {
      // The server holds it, so it IS confirmed; the entry is repaired by the next check or sync.
    }
    return SendOutcome.confirmed;
  }

  /// Whether the server holds this message from this device: true, false
  /// when the server itself answered that it does not, and null when it
  /// could not be asked (offline, or only a cached answer).
  Future<bool?> _onServer(String chatId, String messageId) async {
    peerOf(chatId);
    final ref = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);
    final DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await ref.get(const GetOptions(source: Source.server));
    } catch (_) {
      return null;
    }
    if (snap.metadata.isFromCache) return null;
    final data = snap.data();
    if (!snap.exists || data == null) return false;
    // Someone else's message under this id cannot be ours: not sent.
    return data['senderUid'] == uid &&
        data['senderDevice'] == device.keys.deviceId;
  }

  /// Finishes a message that was saved but whose send did not end (decision
  /// 0059): asks the server, and if the message is not there sends it again
  /// under its own id.
  ///
  /// [SendOutcome.confirmed]: it is sent (now, or it already was).
  /// [SendOutcome.publishUnknown]: could not tell; trying again later is safe.
  /// [SendOutcome.notPublished]: the server refused it, or it cannot be sent
  /// as things are; trying again by itself would not help.
  Future<SendOutcome> finishSend(String chatId, String messageId) async {
    final saved = await _messages.get(chatId, messageId);
    if (saved == null ||
        !saved.outgoing ||
        saved.status != MessageStatus.unconfirmed ||
        saved.mutation != null) {
      return SendOutcome.confirmed; // nothing left to finish
    }
    switch (await _onServer(chatId, messageId)) {
      case true:
        await confirmOwnSend(chatId, messageId);
        return SendOutcome.confirmed;
      case null:
        return SendOutcome.publishUnknown;
      case false:
        break;
    }
    try {
      await sendSaved(saved);
      return SendOutcome.confirmed;
    } on SendNotConfirmedException {
      return SendOutcome.publishUnknown;
    } catch (_) {
      // A refusal can mean an earlier try arrived after the server was
      // asked: the id is taken, by this very message.
      if (await _onServer(chatId, messageId) == true) {
        await confirmOwnSend(chatId, messageId);
        return SendOutcome.confirmed;
      }
      return SendOutcome.notPublished;
    }
  }

  /// Turns our own "unconfirmed" entry into an ordinary sent message. Throws if the local write
  /// fails: during sync that defers the message and holds the cursor, like any other storage
  /// trouble, so the warning is always resolved eventually.
  Future<void> confirmOwnSend(String chatId, String messageId) async {
    final m = await _messages.get(chatId, messageId);
    if (m != null && m.status == MessageStatus.unconfirmed) {
      await _messages.add(m.copyWith(status: MessageStatus.ok));
    }
  }

  /// Writes a message that is KNOWN to be on the server into this device's history (repairs a
  /// failed local save). No server write and no ratchet change.
  Future<void> saveSentLocally({
    required String chatId,
    required String messageId,
    required String body,
    required DateTime sentAt,
  }) => _messages.add(
    LocalMessage(
      id: messageId,
      chatId: chatId,
      senderUid: uid,
      senderDevice: device.keys.deviceId,
      outgoing: true,
      sentAt: sentAt,
      body: body,
    ),
  );

  /// The explicit "send another copy" decision. The original may already have been delivered, so
  /// this is a NEW message: new id, ratchets advanced normally (old counters are never reused).
  /// The warning for the original is removed afterwards.
  Future<void> resendUnconfirmed({
    required String chatId,
    required String messageId,
    required String body,
  }) async {
    final quote = (await _messages.get(chatId, messageId))?.quote;
    if (quote == null) {
      await sendText(chatId, body);
    } else {
      await sendQuoted(chatId, body, quote);
    }
    try {
      await _messages.remove(chatId, messageId);
    } catch (_) {
      // The old warning may linger; it is only a warning.
    }
  }
}

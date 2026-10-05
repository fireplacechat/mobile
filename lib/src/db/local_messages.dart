import 'dart:async';

enum MessageStatus {
  ok,
  undecryptable,

  /// Our own message whose publish outcome is not known: it may or may not have reached the
  /// server. Shown with a warning; never treated as sent, and resolved only by evidence from the
  /// server (see ChatService.checkSendStatus) or by an explicit decision to send another copy.
  unconfirmed,
}

class LocalMessage {
  LocalMessage({
    required this.id,
    required this.chatId,
    required this.senderUid,
    required this.senderDevice,
    required this.outgoing,
    required this.sentAt,
    required this.body,
    this.status = MessageStatus.ok,
  });

  final String id;
  final String chatId;
  final String senderUid;
  final String senderDevice;
  final bool outgoing;
  final DateTime sentAt;
  final String body; // plaintext, or a short reason when undecryptable
  final MessageStatus status;

  Map<String, dynamic> toJson() => {
    'id': id,
    'chatId': chatId,
    'senderUid': senderUid,
    'senderDevice': senderDevice,
    'outgoing': outgoing,
    'sentAt': sentAt.millisecondsSinceEpoch,
    'body': body,
    'status': status.name,
  };

  factory LocalMessage.fromJson(Map<String, dynamic> j) => LocalMessage(
    id: j['id'],
    chatId: j['chatId'],
    senderUid: j['senderUid'],
    senderDevice: j['senderDevice'],
    outgoing: j['outgoing'],
    sentAt: DateTime.fromMillisecondsSinceEpoch(j['sentAt']),
    body: j['body'],
    status: MessageStatus.values.byName(j['status']),
  );
}

/// On-device plaintext history. Ratchet keys are deleted after use, so a message
/// can be decrypted only once; the result MUST be persisted here.
/// The disk-backed, encrypted implementation arrives with the UI (Phase 4).
abstract class LocalMessageStore {
  Future<bool> has(String chatId, String messageId);
  Future<void> add(LocalMessage m);

  /// One stored message, or null.
  Future<LocalMessage?> get(String chatId, String messageId);

  /// Removes one message (used to clear an unconfirmed warning). No-op if absent.
  Future<void> remove(String chatId, String messageId);
  Stream<List<LocalMessage>> watch(String chatId);

  /// Forget a whole conversation on this device.
  Future<void> deleteChat(String chatId);
}

class MemoryMessageStore implements LocalMessageStore {
  final Map<String, Map<String, LocalMessage>> _chats = {};
  final Map<String, StreamController<List<LocalMessage>>> _ctrls = {};

  List<LocalMessage> _sorted(String chatId) =>
      (_chats[chatId]?.values.toList() ?? <LocalMessage>[])
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt));

  @override
  Future<bool> has(String chatId, String messageId) async =>
      _chats[chatId]?.containsKey(messageId) ?? false;

  @override
  Future<void> add(LocalMessage m) async {
    (_chats[m.chatId] ??= {})[m.id] = m;
    _ctrls[m.chatId]?.add(_sorted(m.chatId));
  }

  @override
  Future<LocalMessage?> get(String chatId, String messageId) async =>
      _chats[chatId]?[messageId];

  @override
  Future<void> remove(String chatId, String messageId) async {
    if (_chats[chatId]?.remove(messageId) != null) {
      _ctrls[chatId]?.add(_sorted(chatId));
    }
  }

  @override
  Future<void> deleteChat(String chatId) async {
    _chats.remove(chatId);
    _ctrls[chatId]?.add(const []);
  }

  @override
  Stream<List<LocalMessage>> watch(String chatId) {
    final c = _ctrls[chatId] ??=
        StreamController<List<LocalMessage>>.broadcast();
    return Stream.multi((s) {
      s.add(_sorted(chatId));
      final sub = c.stream.listen(s.add);
      s.onCancel = sub.cancel;
    });
  }
}

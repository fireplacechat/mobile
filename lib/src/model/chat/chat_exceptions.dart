import 'package:fireplace/src/model/chat/chat_service.dart' show ChatService;

/// The server refused a send, so nothing was published. The message is plain words that are safe to show
/// as they are (unlike an arbitrary [ChatException]).
class SendRefusedException extends ChatException {
  SendRefusedException(super.message);
}

class ChatException implements Exception {
  ChatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What is known about an attempt to send a message. "confirmed" means the server accepted the write,
/// not that the other person has received, decrypted or read it.
enum SendOutcome {
  /// The server holds the message.
  confirmed,

  /// Definitely not published (the ordinary errors: the draft can be edited and sent again).
  notPublished,

  /// Published, but this phone could not save it to its own history. Do not send it again.
  publishedLocalSaveFailed,

  /// The network failed in a way that leaves it unknown whether the message was published.
  publishUnknown,
}

/// Thrown by [ChatService.sendText] when the outcome is NOT a clear failure: the message may
/// already have been delivered, so the UI must not invite a plain retry (which could duplicate it).
class SendNotConfirmedException implements Exception {
  const SendNotConfirmedException({
    required this.outcome,
    required this.chatId,
    required this.messageId,
    required this.body,
    required this.attemptedAt,
    required this.persisted,
  });

  /// [SendOutcome.publishUnknown] or [SendOutcome.publishedLocalSaveFailed].
  final SendOutcome outcome;
  final String chatId;

  /// The server document id, stable across [ChatService.checkSendStatus].
  final String messageId;
  final String body;
  final DateTime attemptedAt;

  /// True when an "unconfirmed" entry was saved in the on-device history (so it survives a restart).
  /// False when even that failed: the caller must keep the warning in memory.
  final bool persisted;

  @override
  String toString() => 'Message not confirmed (${outcome.name})';
}

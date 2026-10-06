import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/chat_exceptions.dart';

/// A not-confirmed send whose warning could not be saved on disk, kept for this screen only.
class MemoryPending {
  MemoryPending(SendNotConfirmedException e)
    : messageId = e.messageId,
      body = e.body,
      chatId = e.chatId,
      sentAt = e.attemptedAt,
      outcome = e.outcome;
  final String messageId;
  final String body, chatId;
  final DateTime sentAt;
  SendOutcome outcome;

  LocalMessage asLocalMessage(AppSession? session) => LocalMessage(
    id: messageId,
    chatId: chatId,
    senderUid: session?.uid ?? '',
    senderDevice: session?.device.keys.deviceId ?? '',
    outgoing: true,
    sentAt: sentAt,
    body: body,
    status: outcome == SendOutcome.publishedLocalSaveFailed
        ? MessageStatus.ok
        : MessageStatus.unconfirmed,
  );
}

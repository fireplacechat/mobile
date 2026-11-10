import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/model/chat/chat_exceptions.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';

Future<({MessageQuote? quote, MessageMutation? mutation})>
prepareMessageContent({
  required LocalMessageStore messages,
  required String uid,
  required String chatId,
  required String text,
  MessageQuote? quote,
  MessageMutation? mutation,
  String? replyTarget,
}) async {
  if (messageTooLong(text)) throw ChatException(messageLimitError);
  if (replyTarget != null) {
    final original = await messages.get(chatId, replyTarget);
    if (original == null ||
        !original.visible ||
        original.remotelyDeleted ||
        original.status != MessageStatus.ok) {
      throw ChatException('This message is no longer available to reply to.');
    }
    quote = MessageQuote(
      targetId: original.id,
      senderUid: original.senderUid,
      body: clipMessage(original.body, 1024),
    );
  }
  if (quote != null) {
    quote = MessageQuote.fromJson(quote.toJson());
    final original = await messages.get(chatId, quote.targetId);
    if (original?.remotelyDeleted == true ||
        (original == null && await messages.has(chatId, quote.targetId))) {
      quote = quote.withoutContent();
    }
  }
  if (mutation != null) {
    final target = await messages.get(chatId, mutation.targetId);
    if (target == null ||
        !target.visible ||
        target.remotelyDeleted ||
        target.status != MessageStatus.ok) {
      throw ChatException('This message is no longer available.');
    }
    if (mutation.kind == MessageMutationKind.delete) {
      if (target.senderUid != uid) {
        throw ChatException('Only your messages can be deleted for everyone.');
      }
    } else if (mutation.kind == MessageMutationKind.edit) {
      final age = DateTime.now().difference(target.sentAt);
      if (target.senderUid != uid ||
          age.isNegative ||
          age > const Duration(hours: 24) ||
          target.editClock >= 10) {
        throw ChatException(
          'You can edit your messages up to 10 times within 24 hours.',
        );
      }
      if (mutation.body.trim() == target.body) {
        throw ChatException('Make a change before saving.');
      }
      if (messageTooLong(mutation.body)) throw ChatException(messageLimitError);
      mutation = MessageMutation(
        kind: MessageMutationKind.edit,
        targetId: target.id,
        body: mutation.body.trim(),
        revision: target.editClock + 1,
      );
    } else {
      final previous = target.reactions[uid];
      mutation = MessageMutation(
        kind: MessageMutationKind.reaction,
        targetId: target.id,
        emoji: mutation.emoji,
        operation: previous?.emoji == mutation.emoji
            ? ReactionOperation.clear
            : ReactionOperation.set,
        revision: (target.reactionClocks[uid] ?? previous?.revision ?? 0) + 1,
      );
    }
    mutation = MessageMutation.fromJson(mutation.toJson());
  }
  return (quote: quote, mutation: mutation);
}

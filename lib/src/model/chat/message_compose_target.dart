import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';

enum MessageComposeAction { reply, edit }

class MessageComposeTarget {
  const MessageComposeTarget(this.action, this.message);
  final MessageComposeAction action;
  final LocalMessage message;
  String? get replyId =>
      action == MessageComposeAction.reply ? message.id : null;
}

class MessageCompose extends Notifier<MessageComposeTarget?> {
  MessageCompose(this.chatId);
  final String chatId;
  @override
  MessageComposeTarget? build() {
    ref.watch(appSessionProvider.select((s) => s.value?.uid));
    ref.watch(blockedUidsProvider);
    ref.watch(hiddenChatsProvider);
    ref.watch(identityAlertsProvider);
    return null;
  }

  void reply(LocalMessage message) =>
      state = MessageComposeTarget(MessageComposeAction.reply, message);
  void edit(LocalMessage message) =>
      state = MessageComposeTarget(MessageComposeAction.edit, message);
  void clear() => state = null;
  void clearReply() {
    if (state?.action == MessageComposeAction.reply) state = null;
  }
}

final messageComposeProvider = NotifierProvider.autoDispose
    .family<MessageCompose, MessageComposeTarget?, String>(MessageCompose.new);

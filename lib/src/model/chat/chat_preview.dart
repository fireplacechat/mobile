import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/outgoing_sends.dart';

/// The newest message of a conversation, as the chat list shows it.
@immutable
class ChatPreview {
  const ChatPreview(this.message, {this.notSent = false});

  /// The last saved message, or a send still on its way.
  final LocalMessage message;

  /// A send that failed and waits for the person to decide (see
  /// [OutgoingState.failed]).
  final bool notSent;
}

/// The last saved message, or a send still on its way if that is newer, so a
/// message shows in the chat list the moment it is sent, as it does in the
/// chat itself. Messages deleted for everyone are skipped.
final chatPreviewProvider = Provider.autoDispose.family<ChatPreview?, String>((
  ref,
  chatId,
) {
  final saved = ref.watch(messagesProvider(chatId)).value ?? const [];
  final last = saved.where((m) => !m.remotelyDeleted).lastOrNull;
  OutgoingSend? newest;
  for (final send in ref.watch(outgoingSendsProvider)) {
    if (send.chatId != chatId) continue;
    if (newest == null || send.createdAt.isAfter(newest.createdAt)) {
      newest = send;
    }
  }
  if (newest != null &&
      (last == null || !newest.createdAt.isBefore(last.sentAt))) {
    return ChatPreview(
      LocalMessage(
        id: newest.id,
        chatId: chatId,
        senderUid: '',
        senderDevice: '',
        outgoing: true,
        sentAt: newest.createdAt,
        body: newest.body,
      ),
      notSent: newest.state == OutgoingState.failed,
    );
  }
  return last == null ? null : ChatPreview(last);
});

/// When a conversation last had a message, as far as this phone knows: the
/// server's time, or a newer message saved or being sent here. The server's
/// `lastMessageAt` is moved at most once a minute, so the list orders by this.
DateTime? latestActivity(DateTime? serverTime, ChatPreview? preview) {
  final local = preview?.message.sentAt;
  if (serverTime == null) return local;
  if (local == null) return serverTime;
  return local.isAfter(serverTime) ? local : serverTime;
}

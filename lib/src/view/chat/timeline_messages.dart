import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/memory_pending.dart';
import 'package:fireplace/src/model/chat/outgoing_sends.dart';
import 'package:fireplace/src/view/chat/outgoing_messages.dart';

/// What the chat timeline shows, worked out from what is saved and what is
/// still on its way.
typedef TimelineMessages = ({
  /// Saved history and sends not saved yet, oldest first, without messages
  /// deleted for everyone.
  List<LocalMessage> history,

  /// Index in [history] of the message the person jumped to, or -1.
  int target,

  /// Sends of this chat in flight, by their local id.
  Map<String, OutgoingSend> outgoing,

  /// The rows on screen: [history] with the sends in flight after it, or,
  /// after a jump, [history] up to the message jumped to.
  List<LocalMessage> shown,
});

TimelineMessages timelineMessages({
  required String chatId,
  required List<LocalMessage> stored,
  required Iterable<MemoryPending> pending,
  required AppSession? session,
  required String? location,
  required bool showAll,
  required Iterable<OutgoingSend> outgoingSends,
}) {
  final storedIds = {for (final m in stored) m.id};
  final all =
      [
        ...stored,
        for (final m in pending)
          if (!storedIds.contains(m.messageId)) m.asLocalMessage(session),
      ]..sort((a, b) {
        final byTime = a.sentAt.compareTo(b.sentAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
  final history = [
    for (final message in all)
      if (!message.remotelyDeleted) message,
  ];
  final target = !showAll && location != null
      ? history.indexWhere((m) => m.id == location)
      : -1;
  final outgoing = {
    for (final send in outgoingSends)
      if (send.chatId == chatId) send.id: send,
  };
  final shown = target < 0
      ? [...history, ...outgoingBubbles(outgoing.values, stored, session)]
      : history.take(target + 1).toList();
  return (history: history, target: target, outgoing: outgoing, shown: shown);
}

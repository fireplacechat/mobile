import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fireplace/src/view/chat/message_actions_overlay.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/model/chat/message_selection.dart';
import 'package:fireplace/src/view/chat/message_selection_mark.dart';
import 'package:fireplace/src/view/chat/message_reactions.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/send_controller.dart';
import 'package:fireplace/src/model/chat/outgoing_sends.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/view/chat/widgets/day_separator.dart';
import 'package:fireplace/src/view/chat/widgets/message_bubble.dart';
import 'package:fireplace/src/view/chat/widgets/message_flash.dart';
import 'package:fireplace/src/view/chat/widgets/rising_send.dart';
import 'package:fireplace/src/view/chat/widgets/unconfirmed_note.dart';

class ChatTimeline extends ConsumerWidget {
  // Rebuild with the screen; keep this extraction non-const.
  // ignore: prefer_const_constructors_in_immutables
  ChatTimeline({
    super.key,
    required this.chatId,
    this.onQuote,
    required this.blocked,
    required this.historyFailed,
    required this.loading,
    required this.msgs,
    required this.incomingRequest,
    required this.name,
    required this.awayFromLatest,
    required this.viewportKey,
    required this.scrollController,
    required this.anchorFor,
    required this.send,
    required this.actionsFor,
    required this.onRetryHistory,
    required this.onLatest,
    this.outgoing = const {},
    this.onFailedSend,
    this.flashed,
  });

  /// The message to highlight briefly after a jump to it.
  final ValueListenable<String?>? flashed;

  /// Messages in [msgs] that are being sent or were not sent, by their id.
  final Map<String, OutgoingSend> outgoing;
  final ValueChanged<OutgoingSend>? onFailedSend;
  final bool blocked, historyFailed, loading, incomingRequest, awayFromLatest;
  final List<LocalMessage> msgs;
  final String name;
  final String chatId;
  final ValueChanged<String>? onQuote;
  final GlobalKey viewportKey;
  final ScrollController scrollController;
  final GlobalKey Function(String) anchorFor;
  final SendController send;
  final List<MessageAction> Function(LocalMessage) actionsFor;
  final VoidCallback onRetryHistory, onLatest;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(messageSelectionProvider(chatId));
    final theme = Theme.of(context);
    final highlight = ref
        .watch(chatBubbleColorsProvider)
        .jumpHighlight(
          theme.brightness,
          theme.scaffoldBackgroundColor,
          // Apart from the other person's bubbles, whatever colour they chose.
          other: switch (msgs.where((m) => !m.outgoing).firstOrNull) {
            final theirs? => ref.watch(peerColorProvider(theirs.senderUid)),
            null => ChatBubbleColors.unknown,
          },
        );
    final controller = ref.read(messageSelectionProvider(chatId).notifier);
    return Stack(
      key: viewportKey,
      fit: StackFit.expand,
      children: [
        blocked
            ? const UiEmptyState(
                title: 'Conversation hidden',
                message: 'Unblock this contact in Settings to see your history again.',
              )
            : historyFailed
            ? UiEmptyState(
                title: 'Could not load history',
                message: 'Try again to read the history on this device.',
                action: TextButton(
                  onPressed: onRetryHistory,
                  child: const Text('Try again'),
                ),
              )
            : loading && msgs.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : msgs.isEmpty
            ? UiEmptyState(
                icon: Icons.lock_outline_rounded,
                title: incomingRequest
                    ? 'A new message request'
                    : 'A private conversation',
                message: incomingRequest
                    ? 'Messages stay hidden until you accept.'
                    : 'Messages are end-to-end encrypted. Say hello when you’re ready.',
              )
            : ListView.builder(
                key: const Key('messageTimeline'),
                controller: scrollController,
                reverse: true,
                // The side inset equals the held-message menu's, so a
                // message with room for its menu is lifted without moving.
                padding: const EdgeInsets.symmetric(
                  horizontal: MessageMenuMetrics.edge,
                  vertical: 12,
                ),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final index = msgs.length - 1 - i;
                  final message = msgs[index];
                  final showDate =
                      index == 0 ||
                      !sameLocalDay(msgs[index - 1].sentAt, message.sentAt);
                  final outgoingSend = outgoing[message.id];
                  if (outgoingSend != null) {
                    // Not in the history yet: no menu, reactions or selection.
                    final bubble = MessageBubble(
                      key: anchorFor(message.id),
                      message: message,
                      senderName: name,
                      outgoingSend: outgoingSend,
                      onFailedTap: () => onFailedSend?.call(outgoingSend),
                    );
                    return Column(
                      key: ValueKey(message.id),
                      children: [
                        if (showDate) DaySeparator(date: message.sentAt),
                        if (outgoingSend.state == OutgoingState.sending)
                          RisingSend(child: bubble)
                        else
                          bubble,
                      ],
                    );
                  }
                  final row = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: selection.active
                        ? () => controller.toggle(message.id)
                        : null,
                    child: Stack(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            bottom:
                                message.reactions.values.any(
                                  (reaction) => reaction.emoji != null,
                                )
                                ? ReactionChipLayout.reserve *
                                      MediaQuery.textScalerOf(context).scale(1)
                                : 0,
                          ),
                          child: Row(
                            children: [
                              if (selection.active)
                                MessageSelectionMark(
                                  selected: selection.ids.contains(message.id),
                                ),
                              Expanded(
                                child: MessageBubble(
                                  key: anchorFor(message.id),
                                  message: message,
                                  senderName: name,
                                  selecting: selection.active,
                                  selected: selection.ids.contains(message.id),
                                  onToggleSelection: () =>
                                      controller.toggle(message.id),
                                  actions: actionsFor(message),
                                  onQuote: onQuote,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: selection.active ? 36 : 0,
                          right: 0,
                          child: MessageReactions(
                            message: message,
                            peerName: name,
                            onSelect: selection.active
                                ? () => controller.toggle(message.id)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  );
                  return Column(
                    key: ValueKey(message.id),
                    children: [
                      if (showDate) DaySeparator(date: message.sentAt),
                      if (flashed == null)
                        row
                      else
                        MessageFlash(
                          messageId: message.id,
                          flashed: flashed!,
                          color: highlight,
                          child: row,
                        ),
                      if (!selection.active &&
                          message.outgoing &&
                          !message.remotelyDeleted &&
                          (message.status == MessageStatus.unconfirmed ||
                              send.memoryPending[message.id]?.outcome ==
                                  SendOutcome.publishedLocalSaveFailed))
                        UnconfirmedNote(
                          messageId: message.id,
                          savedLocallyFailed:
                              send.memoryPending[message.id]?.outcome ==
                              SendOutcome.publishedLocalSaveFailed,
                          action: send.messageActions[message.id],
                          note: send.checkNote[message.id],
                          onCheck: () => send.checkStatus(message.id),
                          onSendAgain: () =>
                              send.sendAgain(message.id, message.body),
                          onSave: () {
                            final mem = send.memoryPending[message.id];
                            if (mem != null) {
                              send.saveOnDevice(mem);
                            }
                          },
                        ),
                    ],
                  );
                },
              ),
        if (awayFromLatest && msgs.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 8,
            child: Align(
              alignment: Alignment.bottomRight,
              child: FilledButton(
                key: const Key('latestMessages'),
                // A hairline keeps the button apart from a bubble of the
                // same colour beneath it.
                style: FilledButton.styleFrom(
                  side: const BorderSide(color: Colors.black, width: .5),
                ),
                onPressed: onLatest,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_downward, size: 18),
                    SizedBox(width: 8),
                    Flexible(child: Text('Latest messages')),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

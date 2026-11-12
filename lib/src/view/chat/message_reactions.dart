import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/pending_reactions.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_controls.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/dialog.dart';

const quickReactions = ['❤️', '👍', '👎', '😂', '😮', '😢'];

/// The reaction pill on a message. [reserve] is the space under that message
/// so the pill's center sits on the bubble's bottom edge.
abstract final class ReactionChipLayout {
  static const double height = 26;
  static const double side = 7;
  static const double emoji = 17;
  static const double hang = 13;
  static const double tail = 3;
  static const double reserve = hang + tail;
}

Future<void> confirmRemoteDelete(
  BuildContext context,
  WidgetRef ref,
  LocalMessage message,
) async {
  final owner = ref.read(appSessionProvider).value;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => UiDialog(
      title: const Text('Delete for everyone?'),
      content: const Text(
        'Ask their updated devices to delete this message. They may already have seen or saved it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('confirmRemoteDelete'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Delete for everyone',
            style: TextStyle(color: FireplaceUiTokens.of(ctx).danger),
          ),
        ),
      ],
    ),
  );
  if (!context.mounted ||
      yes != true ||
      !identical(ref.read(appSessionProvider).value, owner)) {
    return;
  }
  await ref
      .read(messageControlsProvider(message.chatId).notifier)
      .delete(message.id);
}

class MessageReactions extends ConsumerWidget {
  const MessageReactions({
    super.key,
    required this.message,
    required this.peerName,
    this.onSelect,
  });
  final LocalMessage message;
  final String peerName;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(appSessionProvider.select((s) => s.value?.uid));
    final groups = <String, int>{};
    for (final reaction in message.reactions.values) {
      final emoji = reaction.emoji;
      if (emoji != null) groups[emoji] = (groups[emoji] ?? 0) + 1;
    }
    if (groups.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: message.outgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          bottom:
              ReactionChipLayout.tail *
              MediaQuery.textScalerOf(context).scale(1),
        ),
        child: Wrap(
          spacing: 4,
          children: [
            for (final group in groups.entries)
              _ReactionChip(
                messageId: message.id,
                emoji: group.key,
                count: group.value,
                mine: message.reactions[uid]?.emoji == group.key,
                onPressed:
                    onSelect ??
                    () => showModalBottomSheet<void>(
                      context: context,
                      useSafeArea: true,
                      showDragHandle: true,
                      builder: (ctx) => Consumer(
                        builder: (ctx, sheetRef, _) {
                          final current = sheetRef
                              .watch(shownMessagesProvider(message.chatId))
                              .value
                              ?.where((m) => m.id == message.id)
                              .firstOrNull;
                          final owner = sheetRef
                              .watch(appSessionProvider)
                              .value
                              ?.uid;
                          final summary = sheetRef.watch(
                            chatSummaryProvider(message.chatId),
                          );
                          sheetRef.watch(blockedUidsProvider);
                          sheetRef.watch(hiddenChatsProvider);
                          sheetRef.watch(identityAlertsProvider);
                          final available =
                              summary != null &&
                              sheetRef
                                  .read(chatActivityProvider.notifier)
                                  .eligible(summary);
                          return SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const ListTile(title: Text('Reactions')),
                                if (owner == uid &&
                                    available &&
                                    current != null)
                                  for (final reaction
                                      in current.reactions.entries)
                                    if (reaction.value.emoji != null)
                                      ListTile(
                                        leading: Text(
                                          reaction.value.emoji!,
                                          style: const TextStyle(fontSize: 28),
                                        ),
                                        title: Text(
                                          reaction.key == uid
                                              ? 'You'
                                              : peerName,
                                        ),
                                        subtitle: reaction.key == uid
                                            ? const Text('Tap to remove')
                                            : null,
                                        onTap: reaction.key == uid
                                            ? () {
                                                Navigator.pop(ctx);
                                                ref
                                                    .read(
                                                      pendingReactionsProvider(
                                                        message.chatId,
                                                      ).notifier,
                                                    )
                                                    .react(
                                                      message.id,
                                                      reaction.value.emoji!,
                                                    );
                                              }
                                            : null,
                                      ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A reaction count. The emoji sits in a fixed square with the same padding
/// on both sides, so the pill's outline is even around it. Height, side
/// padding and the emoji square follow Signal's reaction pill.
class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.messageId,
    required this.emoji,
    required this.count,
    required this.mine,
    required this.onPressed,
  });

  final String messageId;
  final String emoji;
  final int count;
  final bool mine;
  final VoidCallback onPressed;

  static const double _height = ReactionChipLayout.height;
  static const double _side = ReactionChipLayout.side;
  static const double _emoji = ReactionChipLayout.emoji;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final label = '$emoji, $count ${count == 1 ? 'reaction' : 'reactions'}';
    return Semantics(
      button: true,
      label: label,
      child: Material(
        key: ValueKey('reaction-$messageId-$emoji'),
        color: t.panel,
        shape: StadiumBorder(
          side: BorderSide(color: mine ? t.accent : t.separator),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: _side * scale),
            child: SizedBox(
              height: _height * scale,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: _emoji * scale,
                    height: _emoji * scale,
                    child: Transform.translate(
                      // Emoji fonts draw the glyph low in the em square.
                      offset: Offset(0, -1.5 * scale),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        child: Text(
                          emoji,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: _emoji,
                            height: 1,
                            leadingDistribution: TextLeadingDistribution.even,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (count > 1) ...[
                    SizedBox(width: 4 * scale),
                    Text(
                      '$count',
                      style: TextStyle(
                        color: t.text,
                        fontSize: 12 * scale,
                        height: 1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

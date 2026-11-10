import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_controls.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/dialog.dart';

const quickReactions = ['❤️', '👍', '👎', '😂', '😮', '😢'];
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
    final t = FireplaceUiTokens.of(context);
    return Align(
      alignment: message.outgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Wrap(
          spacing: 4,
          children: [
            for (final group in groups.entries)
              OutlinedButton(
                key: ValueKey('reaction-${message.id}-${group.key}'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: t.panel,
                  minimumSize: const Size(44, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  side: BorderSide(
                    color: message.reactions[uid]?.emoji == group.key
                        ? t.accent
                        : t.separator,
                  ),
                  shape: const StadiumBorder(),
                ),
                onPressed:
                    onSelect ??
                    () => showModalBottomSheet<void>(
                      context: context,
                      useSafeArea: true,
                      showDragHandle: true,
                      builder: (ctx) => Consumer(
                        builder: (ctx, sheetRef, _) {
                          final current = sheetRef
                              .watch(messagesProvider(message.chatId))
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
                                                      messageControlsProvider(
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
                child: Text(
                  '${group.key}${group.value > 1 ? ' ${group.value}' : ''}',
                  semanticsLabel:
                      '${group.key}, ${group.value} ${group.value == 1 ? 'reaction' : 'reactions'}',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

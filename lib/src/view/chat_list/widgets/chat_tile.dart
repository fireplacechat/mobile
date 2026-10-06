import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/services/chat_service.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/ui/chat_activity.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/widgets/avatar.dart';

class ChatTile extends ConsumerWidget {
  const ChatTile({super.key, required this.chat, required this.onOpen});
  final ChatSummary chat;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(peerUsernameProvider(chat.peerUid)).value ?? '…';
    final activity = ref.watch(chatActivityProvider);
    final unread = activity.unread[chat.chatId] ?? 0;
    final muted = activity.muted.contains(chat.chatId);
    final held =
        ref.watch(identityAlertsProvider).value?.containsKey(chat.peerUid) ==
        true;
    if (name == deletedAccountLabel) {
      // the other person deleted their account: tidy up this conversation
      ref.watch(peerDeletedCleanupProvider(chat.chatId));
    }
    final msgs = ref.watch(messagesProvider(chat.chatId)).value ?? const [];
    final last = msgs.isEmpty ? null : msgs.last;
    return ListTile(
      key: ValueKey('conversation-${chat.chatId}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: PersonAvatar(name: name),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (last != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  MaterialLocalizations.of(context).formatTimeOfDay(
                    TimeOfDay.fromDateTime(last.sentAt.toLocal()),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        held
            ? 'Messages on hold — review security code'
            : last == null
            ? (!chat.accepted && chat.initiator != null
                  ? 'Waiting for them to accept'
                  : 'Encrypted chat')
            // "(not confirmed)" comes first so the ellipsis never hides it.
            : (last.outgoing
                      ? (last.status == MessageStatus.unconfirmed
                            ? 'You (not confirmed): '
                            : 'You: ')
                      : '') +
                  (last.status == MessageStatus.undecryptable
                      ? 'Unreadable encrypted message'
                      : messagePreview(last.body)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        key: ValueKey('conversationMenu-${chat.chatId}'),
        tooltip: muted ? 'Muted conversation actions' : 'Conversation actions',
        icon: Badge(
          isLabelVisible: unread > 0,
          backgroundColor: muted
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.primary,
          textColor: muted
              ? Theme.of(context).colorScheme.onSurface
              : Colors.white,
          label: Semantics(
            label: '$unread unread messages',
            child: Text(unreadLabel(unread)),
          ),
          key: unread > 0 ? ValueKey('unread-${chat.chatId}') : null,
          child: Icon(
            key: held ? const Key('tileIdentityWarning') : null,
            held
                ? Icons.gpp_maybe
                : muted
                ? Icons.notifications_off_outlined
                : Icons.more_horiz,
            color: held ? Theme.of(context).colorScheme.error : null,
          ),
        ),
        onSelected: (_) async {
          try {
            await ref
                .read(chatActivityProvider.notifier)
                .mute(chat.chatId, !muted);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Could not save the mute preference. Try again.',
                  ),
                ),
              );
            }
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'mute',
            child: Text(muted ? 'Unmute chat' : 'Mute chat'),
          ),
        ],
      ),
      onTap: onOpen,
    );
  }
}

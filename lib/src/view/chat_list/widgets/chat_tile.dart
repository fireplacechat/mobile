import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_preview.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_controls.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat_list/chat_list_stamp.dart';
import 'package:fireplace/src/widgets/avatar.dart';

/// One conversation row: avatar, name and date on the first line, then a
/// two-line preview with the unread count beside its second line.
class ChatTile extends ConsumerWidget {
  const ChatTile({super.key, required this.chat, required this.onOpen});
  final ChatSummary chat;
  final VoidCallback onOpen;

  /// Row geometry shared with the list separator.
  static const double avatarSize = 60;
  static const double edge = 16;
  static const double textInset = edge + avatarSize + 10;

  Future<void> _toggleMute(
    BuildContext context,
    WidgetRef ref,
    bool muted,
  ) async {
    try {
      await ref.read(chatActivityProvider.notifier).mute(chat.chatId, !muted);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the mute preference. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    bool muted, [
    Offset? at,
  ]) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final point = at ?? box.localToGlobal(box.size.center(Offset.zero));
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        point & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'mute',
          child: Text(muted ? 'Unmute chat' : 'Mute chat'),
        ),
      ],
    );
    if (chosen == 'mute' && context.mounted) {
      await _toggleMute(context, ref, muted);
    }
  }

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
    // The newest saved message, or a send still on its way: a message shows
    // here the moment it is sent. A remote delete stays in history so it
    // cannot be replayed, and the row shows the message before it instead.
    final latest = ref.watch(chatPreviewProvider(chat.chatId));
    final last = latest?.message;
    final t = FireplaceUiTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final preview = held
        ? 'Messages on hold — review security code'
        : last == null
        ? (!chat.accepted && chat.initiator != null
              ? 'Waiting for them to accept'
              : 'Encrypted chat')
        // "(not confirmed)" comes first so the ellipsis never hides it.
        : (last.outgoing
                  ? (latest!.notSent
                        ? 'You (not sent): '
                        : last.status == MessageStatus.unconfirmed
                        ? 'You (not confirmed): '
                        : 'You: ')
                  : '') +
              (last.status == MessageStatus.undecryptable
                  ? 'Unreadable encrypted message'
                  : messagePreview(last.body));
    // Sizes are for the default text size and grow with the system setting.
    // At the largest ordinary setting (about 1.35) a row is 104 points with
    // 21 and 20 point text; writing those sizes here would scale them twice.
    final scaler = MediaQuery.textScalerOf(context);
    final nameLine = scaler.scale(16) * 1.2;
    final line = scaler.scale(15) * 1.33;
    var pressedAt = Offset.zero;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu): () =>
            _showActions(context, ref, muted),
        const SingleActivator(LogicalKeyboardKey.f10, shift: true): () =>
            _showActions(context, ref, muted),
      },
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(
            label: muted ? 'Unmute chat' : 'Mute chat',
          ): () =>
              _toggleMute(context, ref, muted),
        },
        child: InkWell(
          key: ValueKey('conversation-${chat.chatId}'),
          onTap: onOpen,
          onTapDown: (details) => pressedAt = details.globalPosition,
          onLongPress: () => _showActions(context, ref, muted, pressedAt),
          onSecondaryTapUp: (details) =>
              _showActions(context, ref, muted, details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: edge),
            child: Row(
              children: [
                PersonAvatar(name: name, size: avatarSize),
                const SizedBox(width: 10),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: avatarSize + 16,
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: scaler.scale(8),
                        bottom: scaler.scale(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The date's smaller type must not stretch the line.
                          SizedBox(
                            height: nameLine,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            height: 1.2,
                                            fontWeight: FontWeight.w600,
                                            color: t.text,
                                          ),
                                        ),
                                      ),
                                      if (held)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 6,
                                          ),
                                          child: Icon(
                                            Icons.gpp_maybe,
                                            key: const Key(
                                              'tileIdentityWarning',
                                            ),
                                            size: scaler.scale(14),
                                            color: scheme.error,
                                            semanticLabel:
                                                'Security code changed',
                                          ),
                                        ),
                                      if (muted)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 6,
                                          ),
                                          child: Icon(
                                            Icons.notifications_off,
                                            key: ValueKey(
                                              'muted-${chat.chatId}',
                                            ),
                                            size: scaler.scale(12),
                                            color: t.secondaryText,
                                            semanticLabel: 'Muted',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (last != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            MediaQuery.sizeOf(context).width *
                                            .45,
                                      ),
                                      child: Text(
                                        chatListStamp(
                                          last.sentAt,
                                          ref.watch(
                                            messageControlNowProvider,
                                          )(),
                                          MaterialLocalizations.of(context),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 16 * 1.2 / 14,
                                          fontWeight: FontWeight.w400,
                                          color: t.secondaryText,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          ConstrainedBox(
                            // The count sits beside the second preview line
                            // even when the preview is shorter.
                            constraints: BoxConstraints(minHeight: line * 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    preview,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      height: 1.33,
                                      fontWeight: FontWeight.w400,
                                      color: t.secondaryText,
                                    ),
                                  ),
                                ),
                                if (unread > 0)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      left: 8,
                                      top:
                                          line +
                                          (line -
                                                  scaler.scale(
                                                    UnreadCount.size,
                                                  )) /
                                              2,
                                    ),
                                    child: UnreadCount(
                                      key: ValueKey('unread-${chat.chatId}'),
                                      count: unread,
                                      muted: muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A filled count: a circle for one digit, a pill for more.
class UnreadCount extends StatelessWidget {
  const UnreadCount({super.key, required this.count, this.muted = false});
  final int count;
  final bool muted;

  /// Height at the default text size.
  static const double size = 20;
  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final size = MediaQuery.textScalerOf(context).scale(UnreadCount.size);
    return Semantics(
      label: '$count unread messages',
      excludeSemantics: true,
      child: Container(
        height: size,
        constraints: BoxConstraints(minWidth: size),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: muted ? t.separator : t.accent,
        ),
        child: Text(
          unreadLabel(count),
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            height: 1,
            fontWeight: FontWeight.w600,
            color: muted ? t.text : Colors.white,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
      ),
    );
  }
}

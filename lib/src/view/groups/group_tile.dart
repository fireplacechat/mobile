import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_controls.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat_list/chat_list_stamp.dart';
import 'package:fireplace/src/view/chat_list/chat_row.dart';
import 'package:fireplace/src/view/groups/group_avatar.dart';
import 'package:fireplace/src/view/groups/group_message_row.dart';

/// A group in the chat list. The row is a 1:1 row (the same avatar size, bold
/// name, date, two-line preview, unread count and spacing) with one
/// difference: the preview names who wrote the newest message
/// ("Mira: See you at 7?"). The avatar is a circle with the group's initial.
class GroupTile extends ConsumerWidget {
  const GroupTile({super.key, required this.group, required this.onOpen});
  final GroupInfo group;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = FireplaceUiTokens.of(context);
    final messages =
        ref.watch(groupMessagesProvider(group.gid)).value ??
        const <LocalMessage>[];
    final last = messages
        .where((m) => m.visible && !m.remotelyDeleted)
        .lastOrNull;
    final invited =
        ref.watch(groupInvitedProvider(group.gid)).value ?? const {};
    final people = group.members
        .where((m) => !invited.containsKey(m.uid))
        .length;
    final unread = ref.watch(groupUnreadProvider(group.gid));
    final notice = last?.status == MessageStatus.notice
        ? GroupNotice.decode(last!.body)
        : null;
    final String preview;
    if (last == null) {
      preview = '$people ${people == 1 ? 'person' : 'people'}';
    } else if (last.status == MessageStatus.notice) {
      preview = notice == null ? '' : groupNoticeText(ref, notice);
    } else {
      final sender = last.outgoing
          ? (last.status == MessageStatus.unconfirmed
                ? 'You (not confirmed)'
                : 'You')
          : ref.watch(peerUsernameProvider(last.senderUid)).value ?? '…';
      preview =
          '$sender: ${last.status == MessageStatus.undecryptable ? 'Unreadable encrypted message' : messagePreview(last.body)}';
    }
    // The same sizes as ChatTile: they are for the default text size and grow
    // with the system setting.
    final scaler = MediaQuery.textScalerOf(context);
    final nameLine = scaler.scale(16) * 1.2;
    final line = scaler.scale(15) * 1.33;
    return InkWell(
      key: Key('group_${group.gid}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ChatTile.edge),
        child: Row(
          children: [
            GroupAvatar(name: group.name, size: ChatTile.avatarSize),
            const SizedBox(width: 10),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: ChatTile.avatarSize + 16,
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
                              child: Text(
                                group.name,
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
                            if (last != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  chatListStamp(
                                    last.sentAt,
                                    ref.watch(messageControlNowProvider)(),
                                    MaterialLocalizations.of(context),
                                  ),
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 16 * 1.2 / 14,
                                    fontWeight: FontWeight.w400,
                                    color: t.secondaryText,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        // The count sits beside the second preview line even
                        // when the preview is shorter.
                        constraints: BoxConstraints(minHeight: line * 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                preview,
                                key: Key('groupPreview_${group.gid}'),
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
                                      (line - scaler.scale(UnreadCount.size)) /
                                          2,
                                ),
                                child: UnreadCount(
                                  key: ValueKey('unread-${group.chatId}'),
                                  count: unread,
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
    );
  }
}

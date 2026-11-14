import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_reactions.dart';
import 'package:fireplace/src/view/chat/message_widgets.dart';
import 'package:fireplace/src/widgets/avatar.dart';

/// Layout shared by the rows of a group conversation.
abstract final class GroupRowMetrics {
  static const double avatar = 30;

  /// The avatar and the gap after it: where other people's bubbles start.
  static const double gutter = avatar + 8;
}

/// One message in a group. The bubble, its held menu and its reactions are the
/// 1:1 ones. A message from someone else also has the sender's name above the
/// first bubble of a run and their avatar beside the last, and uses the soft
/// tint of that member's own colour.
class GroupMessageRow extends ConsumerWidget {
  const GroupMessageRow({
    super.key,
    required this.gid,
    required this.message,
    required this.color,
    required this.showName,
    required this.showAvatar,
    required this.actions,
    required this.onReactions,
  });
  final String gid;
  final LocalMessage message;

  /// The sender's own primary colour (Stone until it arrives).
  final ChatBubbleColor color;
  final bool showName, showAvatar;
  final List<MessageAction> actions;
  final VoidCallback onReactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = message.outgoing;
    final brightness = Theme.of(context).brightness;
    final name = mine
        ? 'You'
        : ref.watch(peerUsernameProvider(message.senderUid)).value ?? '…';
    // A quoted message can be anyone's in the group, not just the sender's.
    final quoted = message.quote?.senderUid;
    final quoteAuthor = quoted == null
        ? null
        : ref.watch(peerUsernameProvider(quoted)).value ?? '…';
    final reserve =
        message.reactions.values.any((reaction) => reaction.emoji != null)
        ? ReactionChipLayout.reserve * MediaQuery.textScalerOf(context).scale(1)
        : 0.0;
    final bubble = Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: reserve),
          child: MessageBubble(
            message: message,
            senderName: name,
            actions: actions,
            incomingColor: mine ? null : color,
            quoteAuthor: quoteAuthor,
            liveOf: (previewRef) => previewRef
                .watch(groupMessagesProvider(gid))
                .value
                ?.where((m) => m.id == message.id)
                .firstOrNull,
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: MessageReactions(
            message: message,
            peerName: name,
            onSelect: onReactions,
          ),
        ),
      ],
    );
    if (mine) return bubble;
    final shade = color.accentText(brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showName)
          Padding(
            padding: const EdgeInsets.only(
              left: GroupRowMetrics.gutter + 14,
              top: 6,
            ),
            child: Text(
              name,
              key: Key('groupSender_${message.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: shade,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: GroupRowMetrics.gutter,
              child: showAvatar
                  ? Padding(
                      // Level with the bubble, above its margin and reactions.
                      padding: EdgeInsets.only(right: 8, bottom: 4 + reserve),
                      child: PersonAvatar(
                        key: Key('groupAvatar_${message.id}'),
                        name: name,
                        size: GroupRowMetrics.avatar,
                        color: shade,
                      ),
                    )
                  : null,
            ),
            Expanded(child: bubble),
          ],
        ),
      ],
    );
  }
}

/// A small centred line in a group's history.
class GroupQuietLine extends StatelessWidget {
  const GroupQuietLine({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        height: 1.3,
        color: FireplaceUiTokens.of(context).secondaryText,
      ),
    ),
  );
}

/// A change to the group ("alice added bob_jones"), with names put in.
class GroupNoticeLine extends ConsumerWidget {
  const GroupNoticeLine({super.key, required this.notice});
  final GroupNotice notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      GroupQuietLine(text: groupNoticeText(ref, notice));
}

/// The words for a notice, with "You" for this account and usernames for
/// everyone else.
String groupNoticeText(WidgetRef ref, GroupNotice notice) {
  final me = ref.watch(appSessionProvider.select((s) => s.value?.uid));
  return notice.text(
    (uid) =>
        uid == me ? 'You' : ref.watch(peerUsernameProvider(uid)).value ?? '…',
  );
}

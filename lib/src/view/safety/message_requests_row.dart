import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_summary.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat_list/chat_row.dart';
import 'package:fireplace/src/view/safety/request_avatar_stack.dart';
import 'package:fireplace/src/view/safety/request_wording.dart';

/// Message requests at the top of the chat list (issue 248), shaped like a
/// chat row: the faces of who is waiting, who they are by username, and how
/// many. Nothing they wrote shows before you accept.
class MessageRequestsRow extends ConsumerWidget {
  const MessageRequestsRow({
    super.key,
    required this.requests,
    required this.invitations,
    required this.onTap,
  });
  final List<ChatSummary> requests;
  final List<GroupInvitation> invitations;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = FireplaceUiTokens.of(context);
    // Newest first, people and invitations together.
    final waiting = <(DateTime, String, bool)>[
      for (final r in requests)
        (r.lastMessageAt ?? DateTime(0), r.peerUid, false),
      for (final i in invitations) (i.at, i.inviter, true),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final names = {
      for (final (_, uid, _) in waiting)
        uid: ref.watch(peerUsernameProvider(uid)).value,
    };
    // Until every name has arrived: plain faces and a general line, never
    // a placeholder.
    final named = !names.values.contains(null);
    final faces = [
      for (final (_, uid, group) in waiting)
        // In the app's own colour: a requester's colour shows only once
        // accepted (decision 0053).
        RequestFace(names[uid] ?? '', group: group),
    ];
    final summary = named
        ? requestSummary([
            for (final (_, uid, group) in waiting)
              WaitingRequest(names[uid]!, group: group),
          ])
        : 'People who want to chat with you';
    final count = waiting.length;
    return Semantics(
      button: true,
      label: 'Message requests, $count waiting',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('requestsTile'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ChatTile.edge,
            vertical: 10,
          ),
          child: Row(
            children: [
              RequestAvatarStack(faces: faces, size: ChatTile.avatarSize),
              const SizedBox(
                width: ChatTile.textInset - ChatTile.edge - ChatTile.avatarSize,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Message requests',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      key: const Key('requestsSummary'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.33,
                        color: t.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              UnreadCount(key: const Key('requestsCount'), count: count),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/widgets/avatar.dart';

class ChatBackButton extends StatelessWidget {
  // Rebuild with the screen; keep this extraction non-const.
  // ignore: prefer_const_constructors_in_immutables
  ChatBackButton({super.key, required this.otherUnread});
  final int otherUnread;
  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('chatBack'),
    tooltip: otherUnread == 0
        ? 'Back to chats'
        : 'Back to chats, $otherUnread unread messages in other chats',
    onPressed: () => Navigator.maybePop(context),
    icon: Badge(
      isLabelVisible: otherUnread > 0,
      label: Text(unreadLabel(otherUnread)),
      child: const BackButtonIcon(),
    ),
  );
}

class ChatTitle extends StatelessWidget {
  // Rebuild with the screen; keep this extraction non-const.
  // ignore: prefer_const_constructors_in_immutables
  ChatTitle({
    super.key,
    required this.name,
    required this.peerUid,
    required this.hasSession,
    required this.onOpenDetails,
  });
  final String name;
  final String? peerUid;
  final bool hasSession;
  final void Function(BuildContext) onOpenDetails;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      PersonAvatar(name: name, size: 36),
      SizedBox(width: 10),
      Expanded(
        child: InkWell(
          key: const Key('chatDetails'),
          onTap: peerUid == null || !hasSession
              ? null
              : () => onOpenDetails(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    ],
  );
}

class ChatVerifyButton extends StatelessWidget {
  // Rebuild with the screen; keep this extraction non-const.
  // ignore: prefer_const_constructors_in_immutables
  ChatVerifyButton({
    super.key,
    required this.verified,
    required this.onPressed,
  });
  final bool verified;
  final void Function(BuildContext) onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    key: Key('verify'),
    tooltip: 'Verify security code',
    icon: Icon(
      verified ? Icons.verified_user : Icons.shield_outlined,
      color: verified ? Theme.of(context).colorScheme.primary : null,
    ),
    onPressed: () => onPressed(context),
  );
}

class ChatOverflowMenu extends StatelessWidget {
  // Rebuild with the screen; keep this extraction non-const.
  // ignore: prefer_const_constructors_in_immutables
  ChatOverflowMenu({
    super.key,
    required this.muted,
    required this.blocked,
    required this.onMute,
    required this.onBlock,
    required this.onUnblock,
    required this.onReport,
  });
  final bool muted, blocked;
  final Future<void> Function() onMute, onBlock, onUnblock, onReport;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    key: Key('chatMenu'),
    onSelected: (v) async {
      if (v == 'mute') {
        await onMute();
      } else if (v == 'block') {
        await onBlock();
      } else if (v == 'unblock') {
        await onUnblock();
      } else if (v == 'report') {
        await onReport();
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        key: const Key('menuMute'),
        value: 'mute',
        child: Text(muted ? 'Unmute chat' : 'Mute chat'),
      ),
      PopupMenuItem(
        key: Key('menuBlock'),
        value: blocked ? 'unblock' : 'block',
        child: Text(blocked ? 'Unblock' : 'Block'),
      ),
      PopupMenuItem(
        key: Key('menuReport'),
        value: 'report',
        child: Text('Report'),
      ),
    ],
  );
}

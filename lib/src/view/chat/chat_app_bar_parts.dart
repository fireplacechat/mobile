import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:fireplace/src/widgets/person_tap.dart';

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

class ChatTitle extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // Their own colour, once the chat is accepted (decision 0053).
    final theirs = peerUid == null
        ? null
        : ref.watch(acceptedPeerColorProvider(peerUid!));
    final open = peerUid == null || !hasSession
        ? null
        : () => onOpenDetails(context);
    // The avatar and the name open the profile; the bar beside them does
    // not (issue 245).
    return Row(
      children: [
        TappableAvatar(
          key: const Key('chatAvatar'),
          onTap: open,
          child: PersonAvatar(name: name, size: 36, color: theirs?.outgoing),
        ),
        SizedBox(width: 6),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TappableName(
              key: const Key('chatDetails'),
              onTap: open,
              child: ChatTitleName(
                name,
                color: theirs?.accentText(Theme.of(context).brightness),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The name at the top of a conversation, 1:1 or group: the size of a name in
/// the chat list. The app bar's own title style is larger and must not apply.
class ChatTitleName extends StatelessWidget {
  const ChatTitleName(this.name, {super.key, this.color});
  final String name;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    name,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 16,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: color ?? FireplaceUiTokens.of(context).text,
    ),
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

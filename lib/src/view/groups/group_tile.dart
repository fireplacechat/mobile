import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/groups/group_avatar.dart';
import 'package:fireplace/src/view/chat_list/chat_list_stamp.dart';

/// A group in the chat list: its avatar, name, and the newest message with
/// who wrote it ("Mira: See you at 7?").
class GroupTile extends ConsumerWidget {
  const GroupTile({super.key, required this.group, required this.onOpen});
  final GroupInfo group;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = FireplaceUiTokens.of(context);
    final messages =
        ref.watch(groupMessagesProvider(group.gid)).value ?? const [];
    final last = messages.where((m) => m.visible).lastOrNull;
    final me = ref.watch(appSessionProvider).value?.uid;
    final sender = last == null
        ? null
        : last.senderUid == me
        ? 'You'
        : ref.watch(peerUsernameProvider(last.senderUid)).value ?? '…';
    final preview = last == null
        ? '${group.members.length} ${group.members.length == 1 ? 'person' : 'people'}'
        : '$sender: ${last.body}';
    return ListTile(
      key: Key('group_${group.gid}'),
      onTap: onOpen,
      leading: GroupAvatar(name: group.name),
      title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: t.secondaryText),
      ),
      trailing: last == null
          ? null
          : Text(
              chatListStamp(
                last.sentAt,
                DateTime.now(),
                MaterialLocalizations.of(context),
              ),
              style: TextStyle(color: t.secondaryText, fontSize: 13),
            ),
    );
  }
}

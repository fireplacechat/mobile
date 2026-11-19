import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/chat/pinned_messages.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/model/groups/group_selection.dart';
import 'package:fireplace/src/styles/action_icons.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_delete_sheet.dart';
import 'package:fireplace/src/view/chat/message_info_sheet.dart';
import 'package:fireplace/src/view/chat/message_menu.dart';
import 'package:fireplace/src/view/chat/message_reactions.dart';
import 'package:fireplace/src/view/chat/message_selection_surface.dart';

/// The held-message menu of a group message: the controls of a 1:1 chat, in
/// the same order and with the same icons (issue 209). Only the author can
/// edit or delete for everyone; every phone enforces that.
List<MessageAction> groupMessageActions(
  LocalMessage message, {
  required String gid,
  required String me,
  required WidgetRef ref,
  required BuildContext context,
  required bool Function() isMounted,
  required void Function(String) notice,
  required Future<void> Function(Future<void> Function()) run,
  required void Function(String emoji) onReact,
  required VoidCallback onReply,
  required VoidCallback onEdit,
  required VoidCallback onDeleting,
}) {
  final readable =
      message.status != MessageStatus.undecryptable && !message.remotelyDeleted;
  final sent = readable && message.status == MessageStatus.ok;
  final chatId = groupChatId(gid);
  return [
    if (sent) ...[
      for (final emoji in quickReactions)
        MessageAction(
          id: 'react-$emoji',
          label: 'React with $emoji',
          icon: Icons.emoji_emotions_outlined,
          reaction: true,
          emoji: emoji,
          selected: message.reactions[me]?.emoji == emoji,
          onSelected: () => onReact(emoji),
        ),
      MessageAction(
        id: 'moreReactions',
        label: 'More reactions',
        icon: Icons.add,
        reaction: true,
        onEmoji: onReact,
        onSelected: () {},
      ),
      MessageAction(
        id: 'reply',
        label: 'Reply',
        icon: CupertinoIcons.arrowshape_turn_up_left,
        onSelected: onReply,
      ),
      if (message.outgoing)
        MessageAction(
          id: 'edit',
          label: 'Edit',
          icon: CupertinoIcons.pencil,
          onSelected: onEdit,
        ),
      if (!messageTooLong(message.body))
        MessageAction(
          id: 'forward',
          label: 'Forward',
          icon: CupertinoIcons.arrowshape_turn_up_right,
          onSelected: () => forwardMessage(
            context,
            message,
            message.outgoing
                ? ''
                : ref.read(peerUsernameProvider(message.senderUid)).value ?? '',
          ),
        ),
    ],
    if (readable)
      MessageAction(
        id: 'copy',
        label: 'Copy',
        icon: ActionIcons.copy,
        onSelected: () =>
            copyMessage(message, isMounted: isMounted, notice: notice),
      ),
    MessageAction(
      id: 'select',
      label: 'Select',
      icon: CupertinoIcons.checkmark_circle,
      onSelected: () =>
          ref.read(groupSelectionProvider(gid).notifier).toggle(message.id),
    ),
    if (readable) ...[
      MessageAction(
        id: 'info',
        label: 'Info',
        icon: CupertinoIcons.info,
        onSelected: () => showMessageInfo(context, message),
      ),
      MessageAction(
        id: 'pin',
        label:
            ref.read(pinnedMessagesProvider)[chatId]?.contains(message.id) ==
                true
            ? 'Unpin'
            : 'Pin',
        icon: CupertinoIcons.pin,
        onSelected: () => ref
            .read(pinnedMessagesProvider.notifier)
            .toggle(chatId, message.id),
      ),
    ],
    MessageAction(
      id: 'delete',
      label: 'Delete',
      icon: ActionIcons.delete,
      destructive: true,
      onSelected: () async {
        final choice = await showMessageDeleteSheet(
          context,
          everyone: message.outgoing && sent,
        );
        final service = ref.read(groupServiceProvider);
        if (choice == null || service == null || !isMounted()) return;
        onDeleting();
        await run(
          () => choice == MessageDeleteChoice.everyone
              ? service.deleteForEveryone(gid, message.id)
              : service.deleteLocally(gid, message.id),
        );
      },
    ),
  ];
}

/// The bar under a group conversation while messages are selected: the one a
/// 1:1 chat shows, acting on this group.
class GroupSelectionBar extends ConsumerWidget {
  const GroupSelectionBar({
    super.key,
    required this.gid,
    required this.onDeleting,
  });
  final String gid;

  /// Before messages go: the screen lets go of any it is editing or quoting.
  final ValueChanged<Set<String>> onDeleting;

  /// The selected messages still here, oldest first.
  List<LocalMessage> _chosen(WidgetRef ref) {
    final ids = ref.read(groupSelectionProvider(gid)).ids;
    return [
      for (final m
          in ref.read(groupMessagesProvider(gid)).value ??
              const <LocalMessage>[])
        if (ids.contains(m.id) && !m.remotelyDeleted) m,
    ];
  }

  void _notice(BuildContext context, String text) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final chosen = _chosen(ref);
    if (chosen.isEmpty) return;
    final choice = await showMessageDeleteSheet(
      context,
      everyone: chosen.every((m) => m.outgoing && m.status == MessageStatus.ok),
      count: chosen.length,
    );
    if (choice == null || !context.mounted) return;
    onDeleting({for (final m in chosen) m.id});
    final done = await ref
        .read(groupSelectionProvider(gid).notifier)
        .delete(chosen, everyone: choice == MessageDeleteChoice.everyone);
    if (!done && context.mounted) {
      _notice(context, 'Could not delete some messages. Try again.');
    }
  }

  Future<void> _copy(BuildContext context, WidgetRef ref) async {
    final text = [
      for (final m in _chosen(ref))
        if (m.status != MessageStatus.undecryptable)
          displayMessage(m.body).plain,
    ].where((body) => body.isNotEmpty).join('\n\n');
    if (text.isEmpty) return;
    var notice = 'Copied';
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      notice = 'Could not copy these messages. Try again.';
    }
    if (context.mounted) _notice(context, notice);
  }

  Future<void> _forward(BuildContext context, WidgetRef ref) async {
    final chosen = [
      for (final m in _chosen(ref))
        if (m.status == MessageStatus.ok) m,
    ];
    if (chosen.isEmpty) return;
    // Named when one other person wrote them all.
    final authors = {
      for (final m in chosen)
        if (!m.outgoing) m.senderUid,
    };
    await forwardMessages(
      context,
      chosen,
      name: authors.length == 1
          ? ref.read(peerUsernameProvider(authors.first)).value ?? ''
          : '',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(groupSelectionProvider(gid));
    return MessageSelectionBar(
      count: selection.ids.length,
      busy: selection.deleting,
      onDelete: () => _delete(context, ref),
      onCopy: () => _copy(context, ref),
      onForward: () => _forward(context, ref),
    );
  }
}

/// Delete All in a group: what you sent is deleted for everyone, the rest on
/// this phone, as in a 1:1 chat.
Future<void> deleteAllGroupMessages(
  BuildContext context,
  WidgetRef ref,
  String gid, {
  required ValueChanged<Set<String>> onDeleting,
}) async {
  if (!await showDeleteAllMessagesSheet(context) || !context.mounted) return;
  final shown = [
    for (final m
        in ref.read(groupMessagesProvider(gid)).value ?? const <LocalMessage>[])
      if (m.visible && !m.remotelyDeleted && m.status != MessageStatus.notice)
        m,
  ];
  onDeleting({for (final m in shown) m.id});
  final done = await ref
      .read(groupSelectionProvider(gid).notifier)
      .deleteAll(shown);
  if (!done && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not delete some messages. Try again.'),
      ),
    );
  }
}

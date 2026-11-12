import 'package:fireplace/src/model/chat/message_compose_target.dart';
import 'package:fireplace/src/model/chat/pending_reactions.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/view/chat/forward/forward_message.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_delete_sheet.dart';
import 'package:fireplace/src/view/chat/message_info_sheet.dart';
import 'package:fireplace/src/model/chat/pinned_messages.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/chat/message_selection.dart';
import 'package:fireplace/src/model/chat/message_controls.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/view/chat/message_reactions.dart';

/// Shared touch, keyboard and screen-reader actions for one message.
List<MessageAction> messageMenuActions(
  LocalMessage message, {
  required WidgetRef ref,
  required BuildContext context,
  required bool Function() isMounted,
  required void Function(String) notice,
  required String Function() chatId,
  required Future<void> Function(Future<void> Function()) contactAction,
  required String name,
  required String? peerUid,
  required bool blocked,
  required bool incomingRequest,
  required bool identityHeld,
}) {
  final owner = ref.read(appSessionProvider).value;
  final now = ref.read(messageControlNowProvider)();
  bool available() {
    if (!isMounted() || owner == null) return false;
    final summary = ref.read(chatSummaryProvider(chatId()));
    final live = ref
        .read(messagesProvider(chatId()))
        .value
        ?.where((m) => m.id == message.id)
        .firstOrNull;
    final pending = ref
        .read(pendingLocalSendsProvider)
        .values
        .any(
          (m) =>
              m.chatId == chatId() &&
              m.messageId == message.id &&
              m.body == message.body,
        );
    return identical(ref.read(appSessionProvider).value, owner) &&
        ((live != null &&
                live.body == message.body &&
                live.remotelyDeleted == message.remotelyDeleted) ||
            pending) &&
        summary != null &&
        ref.read(chatActivityProvider.notifier).eligible(summary);
  }

  void run(VoidCallback action) {
    if (available()) action();
  }

  final readable =
      message.status != MessageStatus.undecryptable && !message.remotelyDeleted;
  final canShare = !incomingRequest && !identityHeld && !blocked && readable;
  return [
    if (canShare &&
        message.status == MessageStatus.ok &&
        ref.read(chatSummaryProvider(chatId()))?.accepted == true) ...[
      for (final emoji in quickReactions)
        MessageAction(
          id: 'react-$emoji',
          label: 'React with $emoji',
          icon: Icons.emoji_emotions_outlined,
          reaction: true,
          emoji: emoji,
          selected: message.reactions[owner?.uid]?.emoji == emoji,
          onSelected: () => run(
            () => ref
                .read(pendingReactionsProvider(chatId()).notifier)
                .react(message.id, emoji),
          ),
        ),
      MessageAction(
        id: 'moreReactions',
        label: 'More reactions',
        icon: Icons.add,
        reaction: true,
        recentEmoji: _recentReactions(ref, chatId(), owner?.uid),
        onEmoji: (emoji) => run(
          () => ref
              .read(pendingReactionsProvider(chatId()).notifier)
              .react(message.id, emoji),
        ),
        onSelected: () {},
      ),
    ],
    if (canShare && message.status == MessageStatus.ok)
      MessageAction(
        id: 'reply',
        label: 'Reply',
        icon: CupertinoIcons.arrowshape_turn_up_left,
        onSelected: () => run(
          () => ref
              .read(messageComposeProvider(chatId()).notifier)
              .reply(message),
        ),
      ),
    if (canShare &&
        message.outgoing &&
        message.status == MessageStatus.ok &&
        message.editClock < 10 &&
        now.difference(message.sentAt) >= Duration.zero &&
        now.difference(message.sentAt) <= const Duration(hours: 24))
      MessageAction(
        id: 'edit',
        label: 'Edit',
        icon: CupertinoIcons.pencil,
        onSelected: () => run(
          () =>
              ref.read(messageComposeProvider(chatId()).notifier).edit(message),
        ),
      ),
    if (canShare &&
        !messageTooLong(message.body) &&
        message.status == MessageStatus.ok)
      MessageAction(
        id: 'forward',
        label: 'Forward',
        icon: CupertinoIcons.arrowshape_turn_up_right,
        onSelected: () => run(() => forwardMessage(context, message, name)),
      ),
    if (canShare)
      MessageAction(
        id: 'copy',
        label: 'Copy',
        icon: CupertinoIcons.doc_on_doc,
        onSelected: () => run(
          () => _copyMessage(message, isMounted: isMounted, notice: notice),
        ),
      ),
    if (!incomingRequest && !identityHeld && !blocked) ...[
      MessageAction(
        id: 'select',
        label: 'Select',
        icon: CupertinoIcons.checkmark_circle,
        onSelected: () => run(
          () => ref
              .read(messageSelectionProvider(chatId()).notifier)
              .toggle(message.id),
        ),
      ),
      if (readable)
        MessageAction(
          id: 'info',
          label: 'Info',
          icon: CupertinoIcons.info,
          onSelected: () => run(() => showMessageInfo(context, message)),
        ),
      if (readable)
        MessageAction(
          id: 'pin',
          label:
              ref
                      .read(pinnedMessagesProvider)[chatId()]
                      ?.contains(message.id) ==
                  true
              ? 'Unpin'
              : 'Pin',
          icon: CupertinoIcons.pin,
          onSelected: () => run(
            () => ref
                .read(pinnedMessagesProvider.notifier)
                .toggle(chatId(), message.id),
          ),
        ),
      MessageAction(
        id: 'delete',
        label: 'Delete',
        icon: CupertinoIcons.trash,
        destructive: true,
        onSelected: () => run(
          () => _deleteMessage(
            context,
            ref,
            message,
            everyone: message.outgoing && message.status == MessageStatus.ok,
          ),
        ),
      ),
    ],
  ];
}

Future<void> _deleteMessage(
  BuildContext context,
  WidgetRef ref,
  LocalMessage message, {
  required bool everyone,
}) async {
  final owner = ref.read(appSessionProvider).value;
  final choice = await showMessageDeleteSheet(context, everyone: everyone);
  final summary = ref.read(chatSummaryProvider(message.chatId));
  if (!context.mounted ||
      choice == null ||
      owner == null ||
      summary == null ||
      !identical(ref.read(appSessionProvider).value, owner) ||
      !ref.read(chatActivityProvider.notifier).eligible(summary)) {
    return;
  }
  if (choice == MessageDeleteChoice.everyone) {
    await ref
        .read(messageControlsProvider(message.chatId).notifier)
        .delete(message.id);
    return;
  }
  await owner.chat.deleteMessageLocally(message.chatId, message.id);
  ref
      .read(pendingLocalSendsProvider.notifier)
      .remove(message.chatId, message.id);
}

Future<void> _copyMessage(
  LocalMessage message, {
  required bool Function() isMounted,
  required void Function(String) notice,
}) async {
  try {
    await Clipboard.setData(
      ClipboardData(text: displayMessage(message.body).plain),
    );
    if (isMounted()) notice('Message copied');
  } catch (_) {
    if (isMounted()) notice('Could not copy this message. Try again.');
  }
}

/// This person's reactions in the conversation, newest message first. Read
/// from the decrypted history already in memory; nothing extra is stored.
List<String> _recentReactions(WidgetRef ref, String chatId, String? uid) {
  if (uid == null) return const [];
  final messages = ref.read(messagesProvider(chatId)).value ?? const [];
  final recent = <String>[];
  for (final message in messages.reversed) {
    final emoji = message.reactions[uid]?.emoji;
    if (emoji != null && !recent.contains(emoji)) recent.add(emoji);
    if (recent.length == 16) break;
  }
  return recent;
}

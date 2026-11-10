import 'package:fireplace/src/model/chat/message_compose_target.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/view/safety/report_dialog.dart';
import 'package:fireplace/src/view/chat/forward/forward_message.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
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
                .read(messageControlsProvider(chatId()).notifier)
                .react(message.id, emoji),
          ),
        ),
      MessageAction(
        id: 'moreReactions',
        label: 'More reactions',
        icon: Icons.add,
        reaction: true,
        onSelected: () => run(() => showReactionPicker(context, ref, message)),
      ),
    ],
    if (canShare && message.status == MessageStatus.ok)
      MessageAction(
        id: 'reply',
        label: 'Reply',
        icon: Icons.reply_rounded,
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
        icon: Icons.edit_outlined,
        onSelected: () => run(
          () =>
              ref.read(messageComposeProvider(chatId()).notifier).edit(message),
        ),
      ),
    if (canShare)
      MessageAction(
        id: 'copy',
        label: 'Copy',
        icon: Icons.copy_outlined,
        onSelected: () => run(
          () => _copyMessage(message, isMounted: isMounted, notice: notice),
        ),
      ),
    if (canShare &&
        !messageTooLong(message.body) &&
        message.status == MessageStatus.ok)
      MessageAction(
        id: 'forward',
        label: 'Forward',
        icon: Icons.forward_outlined,
        onSelected: () => run(() => forwardMessage(context, message, name)),
      ),
    if (canShare)
      MessageAction(
        id: 'selectText',
        label: 'Select text',
        icon: Icons.text_fields_outlined,
        onSelected: () => run(
          () => showSelectTextSheet(
            context,
            displayMessage(message.body).plain,
            protectSelection: (ctx, child) => Consumer(
              builder: (ctx, sheetRef, _) {
                sheetRef.watch(appSessionProvider);
                sheetRef.watch(chatsProvider);
                sheetRef.watch(blockedUidsProvider);
                sheetRef.watch(hiddenChatsProvider);
                sheetRef.watch(identityAlertsProvider);
                sheetRef.watch(messagesProvider(chatId()));
                return available()
                    ? child
                    : const Text(
                        'This conversation is no longer available. Close this sheet and return to your chats.',
                      );
              },
            ),
          ),
        ),
      ),
    if (!incomingRequest && !identityHeld && !blocked)
      MessageAction(
        id: 'select',
        label: 'Select',
        icon: Icons.check_circle_outline,
        onSelected: () => run(
          () => ref
              .read(messageSelectionProvider(chatId()).notifier)
              .toggle(message.id),
        ),
      ),
    // Only another person's message can be reported.
    if (canShare &&
        message.outgoing &&
        message.status == MessageStatus.ok &&
        now.difference(message.sentAt) >= Duration.zero &&
        now.difference(message.sentAt) <= const Duration(hours: 24))
      MessageAction(
        id: 'deleteEveryone',
        label: 'Delete for everyone',
        icon: Icons.delete_outline,
        destructive: true,
        onSelected: () => run(() => confirmRemoteDelete(context, ref, message)),
      ),
    if (!message.outgoing &&
        peerUid != null &&
        !incomingRequest &&
        !identityHeld &&
        !blocked)
      MessageAction(
        id: 'report',
        label: 'Report',
        icon: Icons.flag_outlined,
        destructive: true,
        onSelected: () => run(
          () => contactAction(() async {
            await showReportDialog(
              context,
              ref,
              peerUid: peerUid,
              name: name,
              chatId: chatId(),
              focus: message,
            );
          }),
        ),
      ),
  ];
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

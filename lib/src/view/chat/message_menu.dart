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

/// The long-press menu for one message. Add reply/delete/react here later.
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
  bool available() {
    if (!isMounted() || owner == null) return false;
    final summary = ref.read(chatSummaryProvider(chatId()));
    return identical(ref.read(appSessionProvider).value, owner) &&
        summary != null &&
        ref.read(chatActivityProvider.notifier).eligible(summary);
  }

  void run(VoidCallback action) {
    if (available()) action();
  }

  final readable = message.status != MessageStatus.undecryptable;
  final canShare = !incomingRequest && !identityHeld && !blocked && readable;
  return [
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
    // Only another person's message can be reported.
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

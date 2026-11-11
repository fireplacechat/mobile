import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/model/chat/outgoing_sends.dart';
import 'package:fireplace/src/widgets/dialog.dart';

/// The bubbles for messages that are being sent or failed to send. They go
/// after the history, in the order they were written.
///
/// A send that is already in [history] is left out. The saved row and the
/// optimistic row use different ids, and showing both paints the same text
/// twice. Each saved row covers at most one in-flight send, oldest first, so
/// a second copy of the same text stays visible.
List<LocalMessage> outgoingBubbles(
  Iterable<OutgoingSend> sends,
  List<LocalMessage> history,
  AppSession? session,
) {
  final pending = sends.toList();
  final hidden = _coveredByHistory(pending, history);
  return [
    for (final send in pending)
      if (!hidden.contains(send.id))
        LocalMessage(
          id: send.id,
          chatId: send.chatId,
          senderUid: session?.uid ?? '',
          senderDevice: session?.device.keys.deviceId ?? '',
          outgoing: true,
          sentAt: send.createdAt,
          body: send.body,
          quote: _quoteFor(send.replyTarget, history),
        ),
  ];
}

/// In-flight sends whose text is already stored under an id this send had
/// not seen. A failed send stays: it is the person's choice, not a duplicate.
Set<String> _coveredByHistory(
  List<OutgoingSend> sends,
  List<LocalMessage> history,
) {
  final claimants =
      [
        for (final send in sends)
          if (send.state == OutgoingState.sending && send.historyKnown) send,
      ]..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
  final used = <String>{};
  final hidden = <String>{};
  for (final send in claimants) {
    final candidates =
        [
          for (final message in history)
            if (message.outgoing &&
                !message.remotelyDeleted &&
                message.body == send.body &&
                !send.historyIds.contains(message.id) &&
                !used.contains(message.id))
              message,
        ]..sort((a, b) {
          final byTime = a.sentAt.compareTo(b.sentAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
    final match = candidates.firstOrNull;
    if (match == null) continue;
    used.add(match.id);
    hidden.add(send.id);
  }
  return hidden;
}

MessageQuote? _quoteFor(String? targetId, List<LocalMessage> history) {
  if (targetId == null) return null;
  final target = history.where((m) => m.id == targetId).firstOrNull;
  if (target == null) return null;
  return MessageQuote(
    targetId: target.id,
    senderUid: target.senderUid,
    body: target.body,
  );
}

enum FailedSendChoice { sendAgain, delete }

/// What to do with a message that was not sent. Nothing is sent again unless
/// the person chooses it here.
Future<FailedSendChoice?> showFailedSendDialog(
  BuildContext context,
  OutgoingSend send,
) => showDialog<FailedSendChoice>(
  context: context,
  builder: (ctx) => UiDialog(
    key: const Key('failedSendDialog'),
    title: Text(send.mayHaveArrived ? 'Send not confirmed' : 'Not sent'),
    content: Text(send.error ?? 'This message was not sent.'),
    actions: [
      TextButton(
        key: const Key('failedSendCancel'),
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const Key('failedSendDelete'),
        onPressed: () => Navigator.pop(ctx, FailedSendChoice.delete),
        child: const Text('Delete'),
      ),
      TextButton(
        key: const Key('failedSendAgain'),
        onPressed: () => Navigator.pop(ctx, FailedSendChoice.sendAgain),
        child: const Text('Send again'),
      ),
    ],
  ),
);

/// Asks what to do with a failed message and does it.
Future<void> chooseForFailedSend(
  BuildContext context,
  WidgetRef ref,
  OutgoingSend send, {
  required VoidCallback onSendAgain,
}) async {
  final queue = ref.read(outgoingSendsProvider.notifier);
  final choice = await showFailedSendDialog(context, send);
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case FailedSendChoice.sendAgain:
      queue.sendAgain(send.id);
      onSendAgain();
    case FailedSendChoice.delete:
      queue.delete(send.id);
  }
}

/// A send stopped by a changed security code opens the review once, as a
/// send from the composer always has. Call from a build method.
void reviewIdentityOnFailedSend(
  WidgetRef ref,
  String chatId,
  Future<void> Function(String peerUid, List<int> identityPub) review,
) => ref.listen(outgoingSendsProvider, (previous, next) {
  for (final send in next) {
    final identity = send.identity;
    if (send.chatId != chatId ||
        identity == null ||
        previous?.any((old) => old.id == send.id && old.identity != null) ==
            true) {
      continue;
    }
    review(identity.peerUid, identity.newIdentityPub);
  }
});

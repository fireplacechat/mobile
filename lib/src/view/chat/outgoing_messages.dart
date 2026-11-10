import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/model/chat/outgoing_sends.dart';
import 'package:fireplace/src/widgets/dialog.dart';

/// The bubbles for messages that are being sent or failed to send. They go
/// after the history, in the order they were written.
List<LocalMessage> outgoingBubbles(
  Iterable<OutgoingSend> sends,
  List<LocalMessage> history,
  AppSession? session,
) => [
  for (final send in sends)
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

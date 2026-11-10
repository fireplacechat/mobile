import 'package:flutter/material.dart';
import 'package:fireplace/src/widgets/clock_time.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/model/chat/message_format.dart';

class MessageEditHistory extends ConsumerWidget {
  const MessageEditHistory({
    super.key,
    required this.chatId,
    required this.messageId,
    required this.ownerUid,
  });
  final String chatId, messageId, ownerUid;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(appSessionProvider).value;
    final summary = ref.watch(chatSummaryProvider(chatId));
    ref.watch(blockedUidsProvider);
    ref.watch(hiddenChatsProvider);
    ref.watch(identityAlertsProvider);
    final message = ref
        .watch(messagesProvider(chatId))
        .value
        ?.where((m) => m.id == messageId)
        .firstOrNull;
    final available =
        owner?.uid == ownerUid &&
        summary != null &&
        ref.read(chatActivityProvider.notifier).eligible(summary) &&
        message != null &&
        !message.remotelyDeleted;
    final edits = available
        ? (message.edits.values.toList()
            ..sort((a, b) => b.revision.compareTo(a.revision)))
        : null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Edit history',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (!available)
                const Text('This message is no longer available.')
              else ...[
                for (final edit in edits!) ...[
                  Text(
                    edit == edits.first
                        ? 'Current version'
                        : 'Previous version',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(displayMessage(edit.body).plain),
                  Text(
                    clockTime(edit.sentAt, MaterialLocalizations.of(context)),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Divider(height: 24),
                ],
                Text(
                  'Original message',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  displayMessage(message.originalBody ?? message.body).plain,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

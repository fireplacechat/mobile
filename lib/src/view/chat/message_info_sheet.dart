import 'package:flutter/material.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/clock_time.dart';

/// When this device sent or received the message.
///
/// There is no delivered or read time. Fireplace does not keep those.
Future<void> showMessageInfo(BuildContext context, LocalMessage message) {
  final localizations = MaterialLocalizations.of(context);
  final sent = clockTime(message.sentAt, localizations);
  final day = localizations.formatFullDate(message.sentAt.toLocal());
  final t = FireplaceUiTokens.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: t.panel,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Info', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text(
              message.outgoing ? 'Sent' : 'Received',
              style: Theme.of(ctx).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text('$day, $sent'),
          ],
        ),
      ),
    ),
  );
}

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

/// The messages pinned on this device, newest pin first.
class PinnedBar extends StatelessWidget {
  const PinnedBar({super.key, required this.messages, required this.onOpen});
  final List<LocalMessage> messages;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final newest = messages.first;
    final extra = messages.length - 1;
    return Material(
      color: t.panel,
      child: InkWell(
        key: const Key('pinnedMessages'),
        onTap: () => onOpen(newest.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(CupertinoIcons.pin, size: 16, color: t.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  messagePreview(newest.body),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (extra > 0)
                Text('+$extra', style: TextStyle(color: t.secondaryText)),
            ],
          ),
        ),
      ),
    );
  }
}

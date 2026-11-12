import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/avatar.dart';

/// Recent chats and people who can receive a forwarded message.
class ForwardRecipientList extends ConsumerWidget {
  const ForwardRecipientList({
    super.key,
    required this.chats,
    required this.query,
    required this.finished,
    required this.selected,
    required this.busy,
    required this.canSend,
    required this.onToggle,
  });

  final List<ChatSummary> chats;
  final String query;
  final Map<String, String> finished;
  final Set<String> selected;
  final bool busy;
  final bool Function(ChatSummary chat) canSend;
  final void Function(String chatId, bool selected) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown =
        [
          for (final chat in chats)
            if (canSend(chat) ||
                (finished.containsKey(chat.chatId) &&
                    ref.read(chatActivityProvider.notifier).eligible(chat)))
              chat,
        ].where((chat) {
          final name = ref.read(peerUsernameProvider(chat.peerUid)).value ?? '';
          final text = query.trim().toLowerCase();
          return text.isEmpty || name.toLowerCase().contains(text);
        }).toList();
    final recent = shown.where((chat) => chat.lastMessageAt != null).toList()
      ..sort((a, b) => b.lastMessageAt!.compareTo(a.lastMessageAt!));
    final people = shown.where((chat) => chat.lastMessageAt == null).toList();
    if (shown.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No available recipients. Accepted chats and outgoing requests with room can receive messages.',
          ),
        ),
      );
    }
    return ListView(
      children: [
        if (recent.isNotEmpty) ...[
          const _ForwardHeading('Recent Chats'),
          for (final chat in recent)
            _ForwardRecipient(
              chat: chat,
              selected: selected.contains(chat.chatId),
              done: finished[chat.chatId],
              enabled: !busy && canSend(chat),
              onToggle: onToggle,
            ),
        ],
        if (people.isNotEmpty) ...[
          const _ForwardHeading('People'),
          for (final chat in people)
            _ForwardRecipient(
              chat: chat,
              selected: selected.contains(chat.chatId),
              done: finished[chat.chatId],
              enabled: !busy && canSend(chat),
              onToggle: onToggle,
            ),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(
            'Only the message text is shared. No original sender or conversation details are attached.',
          ),
        ),
      ],
    );
  }
}

class _ForwardRecipient extends ConsumerWidget {
  const _ForwardRecipient({
    required this.chat,
    required this.selected,
    required this.done,
    required this.enabled,
    required this.onToggle,
  });

  final ChatSummary chat;
  final bool selected;
  final String? done;
  final bool enabled;
  final void Function(String chatId, bool selected) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(peerUsernameProvider(chat.peerUid)).value ?? '…';
    final t = FireplaceUiTokens.of(context);
    return InkWell(
      key: ValueKey('forwardRecipient-${chat.chatId}'),
      onTap: enabled ? () => onToggle(chat.chatId, selected) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            PersonAvatar(name: name, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name),
                  if (done != null)
                    Text(done!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? t.accent : Colors.transparent,
                border: Border.all(
                  color: selected ? t.accent : t.secondaryText,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ForwardHeading extends StatelessWidget {
  const _ForwardHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

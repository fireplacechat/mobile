import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_colors.dart';
import 'design_tokens.dart';
import 'presentation.dart';

class ChatAppearanceScreen extends ConsumerWidget {
  const ChatAppearanceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(chatBubbleColorsProvider);
    final t = FireplaceUiTokens.of(context);
    final brightness = Theme.of(context).brightness;
    return Scaffold(
      appBar: UiAppBar(context: context, title: const Text('Chat colors')),
      body: UiPageScroll(
        children: [
          Text(
            'Make it feel like you',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose colors for your messages and the ones you receive.',
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _Preview(
                    label: 'Their messages',
                    color: colors.incoming.incoming(brightness),
                    text: t.incomingText,
                    outgoing: false,
                  ),
                  const SizedBox(height: 12),
                  _Preview(
                    label: 'Your messages',
                    color: colors.outgoing.outgoing,
                    text: Colors.white,
                    outgoing: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          _ColorChoices(
            title: 'Your messages',
            selected: colors.outgoing,
            prefix: 'outgoing',
            swatch: (c) => c.outgoing,
            onSelected: ref.read(chatBubbleColorsProvider.notifier).outgoing,
          ),
          const SizedBox(height: 24),
          _ColorChoices(
            title: 'Their messages',
            selected: colors.incoming,
            prefix: 'incoming',
            swatch: (c) => c.incoming(brightness),
            onSelected: ref.read(chatBubbleColorsProvider.notifier).incoming,
          ),
          const SizedBox(height: 16),
          Text(
            'Applies to all chats while the app is open. Colors reset when the app restarts.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: ref.read(chatBubbleColorsProvider.notifier).reset,
              child: const Text('Reset colors'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorChoices extends StatelessWidget {
  const _ColorChoices({
    required this.title,
    required this.selected,
    required this.prefix,
    required this.swatch,
    required this.onSelected,
  });
  final String title, prefix;
  final ChatBubbleColor selected;
  final Color Function(ChatBubbleColor) swatch;
  final ValueChanged<ChatBubbleColor> onSelected;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final color in ChatBubbleColor.values)
            ChoiceChip(
              key: ValueKey('$prefix-${color.name}'),
              label: Text(
                color.label,
                style: TextStyle(
                  color: FireplaceUiTokens.of(context).text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              selected: selected == color,
              avatar: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: FireplaceUiTokens.of(context).separator,
                  ),
                ),
                child: CircleAvatar(backgroundColor: swatch(color), radius: 8),
              ),
              showCheckmark: true,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => onSelected(color),
            ),
        ],
      ),
    ],
  );
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.label,
    required this.color,
    required this.text,
    required this.outgoing,
  });
  final String label;
  final Color color, text;
  final bool outgoing;
  @override
  Widget build(BuildContext context) => Align(
    alignment: outgoing
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(label, style: TextStyle(color: text)),
    ),
  );
}

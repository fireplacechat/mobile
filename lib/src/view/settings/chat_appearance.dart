import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';

class ChatAppearanceScreen extends ConsumerWidget {
  const ChatAppearanceScreen({super.key});

  /// The choice already shows; this only reports a save that failed.
  Future<void> _save(BuildContext context, Future<void> saving) async {
    try {
      await saving;
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save your color. It will last until the app closes.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(chatBubbleColorsProvider);
    final t = FireplaceUiTokens.of(context);
    final brightness = Theme.of(context).brightness;
    return Scaffold(
      appBar: UiAppBar(context: context, title: const Text('Your color')),
      body: UiPageScroll(
        children: [
          Text(
            'Make it feel like you',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            key: Key('colorExplanation'),
            'Choose colors for your messages in all chats. Your color is also '
            'used for avatars, buttons, and assets within the app.',
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // What your messages look like on other people's phones:
                  // the soft version of the colour you chose.
                  _Preview(
                    key: const Key('theySeePreview'),
                    label: 'They see',
                    color: colors.outgoing.incoming(brightness),
                    text: t.incomingText,
                    outgoing: false,
                  ),
                  const SizedBox(height: 12),
                  _Preview(
                    key: const Key('youSeePreview'),
                    label: 'You see',
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
            title: 'Your color',
            selected: colors.outgoing,
            prefix: 'outgoing',
            swatch: (c) => c.outgoing,
            text: Colors.white,
            onSelected: (color) => _save(
              context,
              ref.read(chatBubbleColorsProvider.notifier).outgoing(color),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Applies to all chats. Your choice is kept on this device. It is '
            'also encrypted in your messages, the server never sees it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => _save(
                context,
                ref.read(chatBubbleColorsProvider.notifier).reset(),
              ),
              child: const Text('Reset color'),
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
    required this.text,
    required this.onSelected,
  });
  final String title, prefix;
  final ChatBubbleColor selected;
  final Color Function(ChatBubbleColor) swatch;
  final Color text;
  final ValueChanged<ChatBubbleColor> onSelected;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      LayoutBuilder(
        builder: (context, box) {
          // Three across when the names fit, fewer with enlarged text.
          final least = MediaQuery.textScalerOf(context).scale(14) * 6.5;
          final columns = (box.maxWidth / least).floor().clamp(1, 3);
          final width = (box.maxWidth / columns).floorToDouble();
          return Wrap(
            children: [
              for (final color in ChatBubbleColor.values)
                SizedBox(
                  width: width,
                  child: ColorBlock(
                    key: ValueKey('$prefix-${color.name}'),
                    label: color.label,
                    color: swatch(color),
                    text: text,
                    selected: selected == color,
                    onTap: () => onSelected(color),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

/// One choice: a block of the colour itself with its name inside. The chosen
/// block has a ring around it, set apart by a gap.
class ColorBlock extends StatelessWidget {
  const ColorBlock({
    super.key,
    required this.label,
    required this.color,
    required this.text,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Color color, text;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Container(
      // The ring's space is always kept, so choosing never moves a block.
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          width: 2,
          color: selected
              ? FireplaceUiTokens.of(context).text
              : Colors.transparent,
        ),
      ),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Preview extends StatelessWidget {
  const _Preview({
    super.key,
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

import 'package:flutter/cupertino.dart';

/// The app's speech bubble: round, with its tail at the lower left. Every
/// speech bubble in the app is this one, never a square (the owner's rule).
const IconData roundBubble = CupertinoIcons.chat_bubble;

/// The round bubble with lines of text in it.
const IconData roundBubbleText = CupertinoIcons.chat_bubble_text;

/// The round bubble with a small [mark] inside it ("!" for a report, a tick
/// for read), sized and coloured by the surrounding [IconTheme] like an
/// [Icon].
class RoundBubbleIcon extends StatelessWidget {
  const RoundBubbleIcon({super.key, required this.mark, this.size, this.color});
  final IconData mark;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final ink = color ?? theme.color;
    return SizedBox.square(
      dimension: side,
      child: Stack(
        children: [
          Icon(roundBubble, size: side, color: ink),
          // In the middle of the round part, above the tail.
          Align(
            alignment: const Alignment(.04, -.2),
            child: Icon(mark, size: side * .46, color: ink),
          ),
        ],
      ),
    );
  }
}

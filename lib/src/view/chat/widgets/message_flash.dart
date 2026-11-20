import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A soft tint behind a message row while [flashed] names it: the row a
/// search result, quote or pin jumped to. It fades in and out, or just
/// appears and goes with reduced motion. [color] comes from the chat colours
/// (ChatBubbleColors.jumpHighlight).
///
/// The tint is a square band as tall as the row that reaches [sideInset]
/// past each side of it. The timeline insets its rows by that much, so the
/// band runs from one screen edge to the other while the row stays put.
class MessageFlash extends StatelessWidget {
  const MessageFlash({
    super.key,
    required this.messageId,
    required this.flashed,
    required this.color,
    required this.sideInset,
    required this.child,
  });

  final String messageId;
  final ValueListenable<String?> flashed;
  final Color color;
  final double sideInset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      // The row is laid out as without the band; the band is painted past it.
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -sideInset,
          right: -sideInset,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: ValueListenableBuilder<String?>(
              valueListenable: flashed,
              builder: (context, id, _) => AnimatedContainer(
                key: ValueKey('messageFlash-$messageId'),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 450),
                curve: Curves.easeOut,
                color: id == messageId ? color : color.withValues(alpha: 0),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

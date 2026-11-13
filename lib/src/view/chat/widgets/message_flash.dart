import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A soft tint behind a message row while [flashed] names it: the row a
/// search result, quote or pin jumped to. It fades in and out, or just
/// appears and goes with reduced motion. [color] comes from the chat colours
/// (ChatBubbleColors.jumpHighlight).
class MessageFlash extends StatelessWidget {
  const MessageFlash({
    super.key,
    required this.messageId,
    required this.flashed,
    required this.color,
    required this.child,
  });

  final String messageId;
  final ValueListenable<String?> flashed;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ValueListenableBuilder<String?>(
      valueListenable: flashed,
      child: child,
      builder: (context, id, child) => AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: id == messageId ? color : color.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      ),
    );
  }
}

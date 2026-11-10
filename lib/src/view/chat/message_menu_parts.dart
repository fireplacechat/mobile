import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';

/// The measured geometry of the held-message menu, in logical pixels.
abstract final class MessageMenuMetrics {
  /// Distance kept from the screen's side edges and from the safe area.
  static const double edge = 16;

  /// Space between the reaction bar, the message and the action list.
  static const double gap = 12;
  static const double barHeight = 56;
  static const double barPadding = 6;
  static const double reactionCell = 44;
  static const double reactionEmoji = 28;
  static const double menuWidth = 250;
  static const double menuRadius = 13;
  static const double rowHeight = 50;
  static const double rowLabel = 22;
  static const double rowIcon = 22;
  static const double rowPadding = 16;
}

/// One quick reaction, or the round button that opens every emoji.
class ReactionBarButton extends StatelessWidget {
  const ReactionBarButton({
    super.key,
    required this.reaction,
    required this.onPressed,
  });
  final MessageAction reaction;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<FireplaceUiTokens>();
    final more = reaction.emoji == null;
    return IconButton(
      key: ValueKey('messageAction-${reaction.id}'),
      tooltip: reaction.label,
      isSelected: reaction.selected,
      style: IconButton.styleFrom(
        fixedSize: const Size(
          MessageMenuMetrics.reactionCell,
          MessageMenuMetrics.barHeight,
        ),
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        // The fill is drawn below at the measured size, not the tap size.
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
      ),
      onPressed: onPressed,
      icon: Container(
        width: MessageMenuMetrics.reactionCell,
        height: MessageMenuMetrics.reactionCell,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: more || reaction.selected
              ? tokens?.separator ?? theme.colorScheme.surfaceContainerHighest
              : null,
        ),
        child: more
            ? Icon(
                CupertinoIcons.ellipsis,
                size: 24,
                color: tokens?.text ?? theme.colorScheme.onSurface,
              )
            : Text(
                reaction.emoji!,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: MessageMenuMetrics.reactionEmoji,
                  height: 1,
                ),
              ),
      ),
    );
  }
}

/// A label with its icon at the trailing edge.
class MessageMenuRow extends StatelessWidget {
  const MessageMenuRow({
    super.key,
    required this.action,
    required this.onPressed,
    this.autofocus = false,
  });
  final MessageAction action;
  final VoidCallback onPressed;
  final bool autofocus;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<FireplaceUiTokens>();
    return TextButton(
      key: ValueKey('messageAction-${action.id}'),
      autofocus: autofocus,
      onPressed: onPressed,
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const WidgetStatePropertyAll(
          Size.fromHeight(MessageMenuMetrics.rowHeight - 1 / 3),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: MessageMenuMetrics.rowPadding,
            vertical: 8,
          ),
        ),
        foregroundColor: WidgetStatePropertyAll(
          action.destructive
              ? tokens?.danger ?? theme.colorScheme.error
              : tokens?.text ?? theme.colorScheme.onSurface,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              action.label,
              style: const TextStyle(
                fontSize: MessageMenuMetrics.rowLabel,
                height: 1.2,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(action.icon, size: MessageMenuMetrics.rowIcon),
        ],
      ),
    );
  }
}

/// Reactions arrive one after another, left to right, as the bar opens.
class ReactionEntrance extends StatelessWidget {
  const ReactionEntrance({
    super.key,
    required this.animation,
    required this.index,
    required this.count,
    required this.child,
  });
  final Animation<double> animation;
  final int index, count;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final start = .5 * index / math.max(1, count);
    final curve = CurvedAnimation(
      parent: animation,
      curve: Interval(start, math.min(1, start + .5), curve: Curves.easeOut),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .35),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }
}

class MessageActionHighlight extends StatelessWidget {
  const MessageActionHighlight({
    super.key,
    required this.action,
    required this.gesture,
    required this.child,
    this.lift = false,
  });
  final MessageAction action;
  final MessageMenuGesture? gesture;
  final Widget child;

  /// Reactions grow and rise under the finger; rows only tint.
  final bool lift;
  @override
  Widget build(BuildContext context) {
    if (gesture == null) return child;
    return ValueListenableBuilder<MessageAction?>(
      valueListenable: gesture!.highlighted,
      builder: (context, highlighted, child) {
        final on = identical(highlighted, action);
        if (lift) {
          return AnimatedSlide(
            offset: on ? const Offset(0, -.4) : Offset.zero,
            duration: const Duration(milliseconds: 150),
            child: AnimatedScale(
              scale: on ? 1.5 : 1,
              duration: const Duration(milliseconds: 150),
              child: child,
            ),
          );
        }
        return ColoredBox(
          color: on
              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: .1)
              : Colors.transparent,
          child: child,
        );
      },
      child: child,
    );
  }
}

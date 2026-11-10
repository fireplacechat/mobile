import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_menu_placement.dart';

/// The measured geometry of the held-message menu, in logical pixels.
abstract final class MessageMenuMetrics {
  /// Distance kept from the screen's side edges and from the safe area.
  static const double edge = 16;

  /// Space between the reaction bar, the message and the action list.
  static const double gap = messageMenuGap;
  static const double barHeight = 56;
  static const double barPadding = 6;
  static const double reactionCell = 44;
  static const double reactionEmoji = 32;
  static const double selectedReaction = 52;
  static const double moreButton = 32;
  static const double menuWidth = 250;
  static const double menuRadius = 12;

  /// Body line box, plus the padding Signal adds underneath it.
  static const double rowLineHeight = 22;
  static const double rowVerticalPadding = 23;
  static const double rowHeight = rowLineHeight + rowVerticalPadding;
  static const double rowHairline = 1 / 3;
  static const double rowLabel = 17;
  static const double rowIcon = 20;
  static const double rowPadding = 16;

  /// `scale(1.5).translatedBy(y: -24)` folds the shift through the scale,
  /// so the focused emoji's center rises 36 points.
  static const double reactionFocusScale = 1.5;
  static const double reactionFocusLift = 36;
  static const Duration reactionFocusDuration = Duration(milliseconds: 150);

  /// Pressed-row wash. Signal's `secondaryFill` (`#787880` at 16% and 32%).
  static const Color rowHighlight = Color(0x29787880);
  static const Color rowHighlightDark = Color(0x52787880);

  /// Hairline under a row. Signal's `transparentSeparator`.
  static const Color rowSeparator = Color(0x5C3C3C43);
  static const Color rowSeparatorDark = Color(0xA6545458);

  static Color highlightFor(Brightness brightness) =>
      brightness == Brightness.dark ? rowHighlightDark : rowHighlight;

  static Color separatorFor(Brightness brightness) =>
      brightness == Brightness.dark ? rowSeparatorDark : rowSeparator;
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
    final emojiSize = MediaQuery.sizeOf(context).width < 375
        ? 30.0
        : MessageMenuMetrics.reactionEmoji;
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
        backgroundColor: Colors.transparent,
        overlayColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        shape: const RoundedRectangleBorder(),
      ),
      enableFeedback: false,
      onPressed: onPressed,
      icon: SizedBox(
        width: MessageMenuMetrics.reactionCell,
        height: MessageMenuMetrics.barHeight,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (reaction.selected)
              Container(
                width: MessageMenuMetrics.selectedReaction,
                height: MessageMenuMetrics.selectedReaction,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MessageMenuMetrics.highlightFor(theme.brightness),
                ),
              ),
            if (more)
              Container(
                width: MessageMenuMetrics.moreButton,
                height: MessageMenuMetrics.moreButton,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      tokens?.separator ??
                      theme.colorScheme.surfaceContainerHighest,
                ),
                child: Icon(
                  Icons.add,
                  size: 20,
                  color: tokens?.secondaryText ?? theme.colorScheme.onSurface,
                ),
              )
            else
              Text(
                reaction.emoji!,
                textScaler: TextScaler.noScaling,
                style: TextStyle(fontSize: emojiSize, height: 1),
              ),
          ],
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
    this.divider = false,
  });
  final MessageAction action;
  final VoidCallback onPressed;
  final bool autofocus;

  /// Hairline along the bottom edge. The last row leaves this off.
  final bool divider;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<FireplaceUiTokens>();
    const rowHeight = MessageMenuMetrics.rowHeight;
    return TextButton(
      key: ValueKey('messageAction-${action.id}'),
      autofocus: autofocus,
      onPressed: onPressed,
      style:
          const ButtonStyle(
            shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStatePropertyAll(Colors.transparent),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.standard,
            minimumSize: WidgetStatePropertyAll(Size(0, rowHeight)),
            maximumSize: WidgetStatePropertyAll(
              Size(double.infinity, rowHeight),
            ),
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
            alignment: Alignment.center,
            enableFeedback: false,
          ).copyWith(
            foregroundColor: WidgetStatePropertyAll(
              action.destructive
                  ? tokens?.danger ?? theme.colorScheme.error
                  : tokens?.text ?? theme.colorScheme.onSurface,
            ),
          ),
      // The highlight is the row's own bounds, and the hairline sits inside
      // that bounds rather than adding space between rows.
      child: SizedBox(
        height: rowHeight,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MessageMenuMetrics.rowPadding,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      action.label,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: MessageMenuMetrics.rowLabel,
                        height:
                            MessageMenuMetrics.rowLineHeight /
                            MessageMenuMetrics.rowLabel,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(action.icon, size: MessageMenuMetrics.rowIcon),
                ],
              ),
            ),
            if (divider)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: MessageMenuMetrics.rowHairline,
                child: ColoredBox(
                  color: MessageMenuMetrics.separatorFor(theme.brightness),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Each reaction rises into the bar a moment after the one before it.
class ReactionEntrance extends StatelessWidget {
  const ReactionEntrance({
    super.key,
    required this.animation,
    required this.index,
    required this.child,
  });
  final Animation<double> animation;
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    // The bar's own animation is 400ms. Each emoji takes 200ms and starts 10ms
    // after the previous one, rising 24px.
    final start = math.min(.5, index * 10 / 400);
    final curve = CurvedAnimation(
      parent: animation,
      curve: Interval(start, math.min(1, start + .5), curve: Curves.easeIn),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) {
        final t = curve.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Grows the emoji under the finger. Signal's matrix is
/// `scale(1.5).translatedBy(y: -24)`, which lifts the center 36 points.
class _ReactionFocus extends StatefulWidget {
  const _ReactionFocus({required this.focused, required this.child});

  final bool focused;
  final Widget child;

  @override
  State<_ReactionFocus> createState() => _ReactionFocusState();
}

class _ReactionFocusState extends State<_ReactionFocus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _focus;

  @override
  void initState() {
    super.initState();
    _focus = AnimationController(
      vsync: this,
      duration: MessageMenuMetrics.reactionFocusDuration,
      value: widget.focused ? 1 : 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _focus.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : MessageMenuMetrics.reactionFocusDuration;
  }

  @override
  void didUpdateWidget(_ReactionFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused == oldWidget.focused) return;
    // A reduced-motion duration of zero has no frames to play.
    if (_focus.duration == Duration.zero) {
      _focus.value = widget.focused ? 1 : 0;
    } else if (widget.focused) {
      _focus.forward();
    } else {
      _focus.reverse();
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _focus,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_focus.value);
        return Transform.translate(
          offset: Offset(0, -MessageMenuMetrics.reactionFocusLift * t),
          child: Transform.scale(
            scale: 1 + (MessageMenuMetrics.reactionFocusScale - 1) * t,
            child: child,
          ),
        );
      },
      child: widget.child,
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
          return _ReactionFocus(focused: on, child: child!);
        }
        return ColoredBox(
          color: on
              ? MessageMenuMetrics.highlightFor(Theme.of(context).brightness)
              : Colors.transparent,
          child: child,
        );
      },
      child: child,
    );
  }
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_actions_controls.dart';
import 'package:fireplace/src/view/chat/message_menu_parts.dart';
import 'package:fireplace/src/view/chat/message_menu_stack.dart';

export 'package:fireplace/src/view/chat/message_menu_parts.dart';

/// A short settle. Exactly 0 at the start and 1 at the end, so a message that
/// has room does not drift and a raised one lands on its measured edge.
class _MenuSpring extends Curve {
  const _MenuSpring();
  @override
  double transformInternal(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return (1 - math.exp(-6 * t) * math.cos(8 * t)).clamp(0.0, 1.0);
  }
}

/// The held message stays solid. The scrim, reaction bar and action list
/// animate around it.
class MessageActionsOverlay extends StatelessWidget {
  const MessageActionsOverlay({
    super.key,
    required this.anchor,
    required this.actions,
    required this.animation,
    required this.onSelected,
    this.reactions = const [],
    this.gesture,
    this.preview,
    this.controls,
    this.picker,
    this.pickerTop = double.infinity,
    this.onReleased,
  });

  final Rect anchor;
  final List<MessageAction> actions;
  final List<MessageAction> reactions;
  final MessageMenuGesture? gesture;
  final Animation<double> animation;
  final ValueChanged<MessageAction> onSelected;
  final Widget? preview;

  /// Fades the reaction bar and action list out while the message stays, for
  /// the emoji picker that replaces them. Null keeps them visible.
  final Animation<double>? controls;

  /// How far the emoji picker has opened (0 to 1) and the top edge it rests
  /// at. A message it would cover rises to stay readable above it.
  final Animation<double>? picker;
  final double pickerTop;

  /// A finger that slid away from the press and came up off every control.
  final VoidCallback? onReleased;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final tokens = theme.extension<FireplaceUiTokens>();
    final panel = tokens?.panel ?? theme.colorScheme.surface;
    final targets = {
      for (final a in [...reactions, ...actions]) a: GlobalKey(),
    };
    final panelKey = GlobalKey();
    bool contains(GlobalKey key, Offset point, {bool expanded = false}) {
      final render = key.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return false;
      var rect = render.localToGlobal(Offset.zero) & render.size;
      if (expanded) {
        // The focused emoji sits above the bar, so the finger can follow it.
        rect = Rect.fromLTWH(rect.left - 3, rect.top - 20, rect.width + 6, 136);
      }
      return rect.contains(point);
    }

    MessageAction? reactionAt(Offset point) {
      if (contains(panelKey, point)) return null;
      for (final entry in targets.entries) {
        if (entry.key.reaction &&
            contains(entry.value, point, expanded: true)) {
          return entry.key;
        }
      }
      return null;
    }

    MessageAction? rowAt(Offset point) {
      if (!contains(panelKey, point)) return null;
      for (final entry in targets.entries) {
        if (!entry.key.reaction && contains(entry.value, point)) {
          return entry.key;
        }
      }
      return null;
    }

    void highlight(MessageAction? chosen) {
      final finger = gesture;
      if (finger == null || identical(finger.highlighted.value, chosen)) {
        return;
      }
      final previous = finger.highlighted.value;
      finger.highlighted.value = chosen;
      final kind = chosen ?? previous;
      if (kind == null) return;
      final feedback = kind.reaction
          ? HapticFeedback.selectionClick()
          : HapticFeedback.lightImpact();
      feedback.catchError((Object _) {});
    }

    void choose(MessageAction action) {
      final finger = gesture;
      if (finger == null) {
        onSelected(action);
      } else {
        finger.choose(() => onSelected(action));
      }
    }

    if (gesture != null) {
      gesture!.onMove = (point) {
        if (!gesture!.allowsHighlight(point)) {
          highlight(null);
          return;
        }
        highlight(rowAt(point) ?? reactionAt(point));
      };
      gesture!.onEnd = () {
        if (!context.mounted) return;
        final chosen = gesture!.highlighted.value;
        if (chosen != null) {
          choose(chosen);
        } else if (gesture!.armed) {
          onReleased?.call();
        }
      };
    }
    final alignEnd = anchor.center.dx > media.size.width / 2;
    final shown = controls ?? const AlwaysStoppedAnimation(1.0);
    final grow = CurvedAnimation(
      parent: animation,
      curve: const _MenuSpring(),
      reverseCurve: Curves.easeInOut,
    );
    Widget fading(Widget child) => FadeTransition(
      opacity: shown,
      child: AnimatedBuilder(
        animation: shown,
        builder: (context, child) =>
            IgnorePointer(ignoring: shown.value < 1, child: child),
        child: child,
      ),
    );
    final scrim = theme.brightness == Brightness.dark
        ? const Color(0x33FFFFFF)
        : const Color(0x33000000);
    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: const Interval(0, .5, curve: Curves.easeOut),
              reverseCurve: Curves.easeIn,
            ),
            child: IgnorePointer(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: ColoredBox(color: scrim),
              ),
            ),
          ),
        ),
        Positioned.fill(
          // The overlay sits outside the page Material. Without a text style
          // here, the held message inherits MaterialApp's fallback: a double
          // yellow underline.
          child: DefaultTextStyle(
            style: theme.textTheme.bodyMedium!.copyWith(
              decoration: TextDecoration.none,
            ),
            child: MessageMenuStack(
              anchor: anchor,
              insets: EdgeInsets.fromLTRB(
                media.padding.left + MessageMenuMetrics.edge,
                media.padding.top + MessageMenuMetrics.edge,
                media.padding.right + MessageMenuMetrics.edge,
                math.max(
                  math.max(media.padding.bottom, media.viewInsets.bottom),
                  MessageMenuMetrics.edge,
                ),
              ),
              shift: grow,
              picker: picker ?? const AlwaysStoppedAnimation(0),
              pickerTop: pickerTop,
              children: [
                if (preview != null)
                  MessageMenuId(
                    id: 'preview',
                    child: IgnorePointer(
                      child: ExcludeSemantics(child: preview!),
                    ),
                  ),
                if (reactions.isNotEmpty)
                  MessageMenuId(
                    id: 'reactions',
                    child: fading(
                      MessageReactionBar(
                        animation: animation,
                        panel: panel,
                        reactions: reactions,
                        targets: targets,
                        gesture: gesture,
                        onPoint: (point) => highlight(reactionAt(point)),
                        onRelease: () {
                          final chosen = gesture?.highlighted.value;
                          gesture?.highlighted.value = null;
                          if (chosen != null && chosen.reaction) {
                            choose(chosen);
                          }
                        },
                        onChoose: choose,
                      ),
                    ),
                  ),
                MessageMenuId(
                  id: 'menu',
                  child: fading(
                    MessageActionsPanel(
                      animation: animation,
                      grow: grow,
                      alignEnd: alignEnd,
                      panel: panel,
                      panelKey: panelKey,
                      actions: actions,
                      targets: targets,
                      gesture: gesture,
                      onPoint: (point) => highlight(rowAt(point)),
                      onRelease: () {
                        final chosen = gesture?.highlighted.value;
                        gesture?.highlighted.value = null;
                        if (chosen != null && !chosen.reaction) {
                          choose(chosen);
                        }
                      },
                      onChoose: choose,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

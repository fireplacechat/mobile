import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_menu_parts.dart';

export 'package:fireplace/src/view/chat/message_menu_parts.dart';

/// A lifted message and its actions share an edge, even near the keyboard.
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

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final tokens = theme.extension<FireplaceUiTokens>();
    final panel = tokens?.panel ?? theme.colorScheme.surface;
    final targets = {
      for (final a in [...reactions, ...actions]) a: GlobalKey(),
    };
    final panelKey = GlobalKey(), reactionKey = GlobalKey();
    bool contains(GlobalKey key, Offset point) {
      final render = key.currentContext?.findRenderObject();
      return render is RenderBox &&
          (render.localToGlobal(Offset.zero) & render.size).contains(point);
    }

    if (gesture != null) {
      gesture!.onMove = (point) {
        MessageAction? chosen;
        for (final entry in targets.entries) {
          if (contains(entry.key.reaction ? reactionKey : panelKey, point) &&
              contains(entry.value, point)) {
            chosen = entry.key;
            break;
          }
        }
        gesture!.highlighted.value = chosen;
      };
      gesture!.onEnd = () {
        final chosen = gesture!.highlighted.value;
        if (chosen != null && context.mounted) onSelected(chosen);
      };
    }
    final right = anchor.center.dx > media.size.width / 2;
    final shown = controls ?? const AlwaysStoppedAnimation(1.0);
    // The list grows out of the message corner it hangs from.
    final grow = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
    Widget fading(Widget child) => FadeTransition(
      opacity: shown,
      child: AnimatedBuilder(
        animation: shown,
        builder: (context, child) =>
            IgnorePointer(ignoring: shown.value < 1, child: child),
        child: child,
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: ColoredBox(
                color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? .4 : .2,
                ),
              ),
            ),
          ),
        ),
        CustomMultiChildLayout(
          delegate: _MessageMenuLayout(
            anchor,
            // A message too low for its menu slides up; one with room stays.
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            picker ?? const AlwaysStoppedAnimation(0),
            pickerTop,
            EdgeInsets.fromLTRB(
              media.padding.left + MessageMenuMetrics.edge,
              media.padding.top + MessageMenuMetrics.edge,
              media.padding.right + MessageMenuMetrics.edge,
              math.max(
                math.max(media.padding.bottom, media.viewInsets.bottom),
                MessageMenuMetrics.edge,
              ),
            ),
          ),
          children: [
            if (reactions.isNotEmpty)
              LayoutId(
                id: _Part.reactions,
                child: fading(
                  KeyedSubtree(
                    key: reactionKey,
                    child: Material(
                      key: const Key('messageReactionBar'),
                      elevation: 8,
                      color: panel,
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: MessageMenuMetrics.barPadding,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (index, reaction) in reactions.indexed)
                              ReactionEntrance(
                                animation: animation,
                                index: index,
                                count: reactions.length,
                                child: MessageActionHighlight(
                                  key: targets[reaction],
                                  action: reaction,
                                  gesture: gesture,
                                  lift: true,
                                  child: ReactionBarButton(
                                    reaction: reaction,
                                    onPressed: () => onSelected(reaction),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (preview != null)
              LayoutId(
                id: _Part.preview,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Material(
                      type: MaterialType.transparency,
                      child: SingleChildScrollView(child: preview!),
                    ),
                  ),
                ),
              ),
            LayoutId(
              id: _Part.menu,
              child: fading(
                ScaleTransition(
                  scale: Tween(begin: .2, end: 1.0).animate(grow),
                  alignment: right ? Alignment.topRight : Alignment.topLeft,
                  child: KeyedSubtree(
                    key: panelKey,
                    child: Material(
                      key: const Key('messageActionsPanel'),
                      elevation: 12,
                      color: panel,
                      borderRadius: BorderRadius.circular(
                        MessageMenuMetrics.menuRadius,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (index, action) in actions.indexed) ...[
                              if (index != 0)
                                Divider(
                                  height: 1 / 3,
                                  thickness: 1 / 3,
                                  color: tokens?.separator,
                                ),
                              MessageActionHighlight(
                                key: targets[action],
                                action: action,
                                gesture: gesture,
                                child: MessageMenuRow(
                                  action: action,
                                  autofocus: index == 0,
                                  onPressed: () => onSelected(action),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _Part { preview, menu, reactions }

class _MessageMenuLayout extends MultiChildLayoutDelegate {
  _MessageMenuLayout(
    this.anchor,
    this.shift,
    this.picker,
    this.pickerTop,
    this.insets,
  ) : super(relayout: Listenable.merge([shift, picker]));
  final Animation<double> picker;
  final double pickerTop;
  final Rect anchor;

  /// 0 keeps the message where it was held; 1 is where everything fits.
  final Animation<double> shift;
  final EdgeInsets insets;

  @override
  void performLayout(Size size) {
    final area = Rect.fromLTRB(
      insets.left,
      insets.top,
      math.max(insets.left, size.width - insets.right),
      math.max(insets.top, size.height - insets.bottom),
    );
    const gap = MessageMenuMetrics.gap;
    final hasPreview = hasChild(_Part.preview);
    final hasReactions = hasChild(_Part.reactions);
    final reactionSize = hasReactions
        ? layoutChild(
            _Part.reactions,
            BoxConstraints(
              maxWidth: area.width,
              minHeight: math.min(MessageMenuMetrics.barHeight, area.height),
              maxHeight: math.min(MessageMenuMetrics.barHeight, area.height),
            ),
          )
        : Size.zero;
    final reactionHeight = hasReactions ? reactionSize.height + gap : 0.0;
    final menuWidth = math.min(MessageMenuMetrics.menuWidth, area.width);
    final menu = layoutChild(
      _Part.menu,
      BoxConstraints(
        minWidth: menuWidth,
        maxWidth: menuWidth,
        maxHeight:
            math.max(0, area.height - reactionHeight) * (hasPreview ? .7 : 1),
      ),
    );
    final preview = hasPreview
        ? layoutChild(
            _Part.preview,
            BoxConstraints(
              maxWidth: math.min(anchor.width, area.width),
              maxHeight: math.max(
                0,
                area.height - reactionHeight - menu.height - gap,
              ),
            ),
          )
        : Size.zero;
    final right = anchor.center.dx > size.width / 2;
    double x(double width) => (right ? anchor.right - width : anchor.left)
        .clamp(area.left, math.max(area.left, area.right - width));
    final height =
        reactionHeight + preview.height + (hasPreview ? gap : 0) + menu.height;
    final held = anchor.top - reactionHeight;
    final fits = held
        .clamp(area.top, math.max(area.top, area.bottom - height))
        .toDouble();
    final top = held + (fits - held) * shift.value;
    if (hasReactions) {
      positionChild(_Part.reactions, Offset(x(reactionSize.width), top));
    }
    if (hasPreview) {
      final inMenu = top + reactionHeight;
      final abovePicker = math.max(
        area.top,
        math.min(inMenu, pickerTop - gap - preview.height),
      );
      positionChild(
        _Part.preview,
        Offset(
          x(preview.width),
          inMenu + (abovePicker - inMenu) * picker.value,
        ),
      );
    }
    positionChild(
      _Part.menu,
      Offset(
        x(menu.width),
        top + reactionHeight + preview.height + (hasPreview ? gap : 0),
      ),
    );
  }

  @override
  bool shouldRelayout(_MessageMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      insets != oldDelegate.insets ||
      pickerTop != oldDelegate.pickerTop;
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';

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
  });

  final Rect anchor;
  final List<MessageAction> actions;
  final List<MessageAction> reactions;
  final MessageMenuGesture? gesture;
  final Animation<double> animation;
  final ValueChanged<MessageAction> onSelected;
  final Widget? preview;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final tokens = theme.extension<FireplaceUiTokens>();
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
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: ColoredBox(color: Colors.black.withValues(alpha: .22)),
            ),
          ),
        ),
        CustomMultiChildLayout(
          delegate: _MessageMenuLayout(
            anchor,
            EdgeInsets.fromLTRB(
              media.padding.left + 12,
              media.padding.top + 12,
              media.padding.right + 12,
              math.max(media.padding.bottom, media.viewInsets.bottom) + 12,
            ),
          ),
          children: [
            if (reactions.isNotEmpty)
              LayoutId(
                id: _Part.reactions,
                child: KeyedSubtree(
                  key: reactionKey,
                  child: Material(
                    key: const Key('messageReactionBar'),
                    elevation: 8,
                    color: tokens?.panel ?? theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(32),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final reaction in reactions)
                            MessageActionHighlight(
                              key: targets[reaction],
                              action: reaction,
                              gesture: gesture,
                              child: IconButton(
                                key: ValueKey('messageAction-${reaction.id}'),
                                tooltip: reaction.label,
                                isSelected: reaction.selected,
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(44, 44),
                                  backgroundColor: reaction.selected
                                      ? tokens?.selectedRow
                                      : null,
                                ),
                                onPressed: () => onSelected(reaction),
                                icon: reaction.emoji == null
                                    ? Icon(reaction.icon)
                                    : Text(
                                        reaction.emoji!,
                                        textScaler: TextScaler.noScaling,
                                        style: const TextStyle(fontSize: 28),
                                      ),
                              ),
                            ),
                        ],
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
              child: ScaleTransition(
                scale: Tween(begin: .8, end: 1.0).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                ),
                alignment: anchor.center.dx > media.size.width / 2
                    ? Alignment.topRight
                    : Alignment.topLeft,
                child: KeyedSubtree(
                  key: panelKey,
                  child: Material(
                    key: const Key('messageActionsPanel'),
                    elevation: 12,
                    color: tokens?.panel ?? theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (index, action) in actions.indexed) ...[
                            if (index != 0)
                              Divider(
                                height: 1,
                                thickness: .5,
                                color: tokens?.separator,
                              ),
                            MessageActionHighlight(
                              key: targets[action],
                              action: action,
                              gesture: gesture,
                              child: TextButton(
                                key: ValueKey('messageAction-${action.id}'),
                                autofocus: index == 0,
                                onPressed: () => onSelected(action),
                                style: ButtonStyle(
                                  shape: const WidgetStatePropertyAll(
                                    RoundedRectangleBorder(),
                                  ),
                                  minimumSize: const WidgetStatePropertyAll(
                                    Size.fromHeight(48),
                                  ),
                                  padding: const WidgetStatePropertyAll(
                                    EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
                                  ),
                                  foregroundColor: WidgetStatePropertyAll(
                                    action.destructive
                                        ? tokens?.danger ??
                                              theme.colorScheme.error
                                        : tokens?.text ??
                                              theme.colorScheme.onSurface,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        action.label,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(action.icon, size: 22),
                                  ],
                                ),
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
          ],
        ),
      ],
    );
  }
}

class MessageActionHighlight extends StatelessWidget {
  const MessageActionHighlight({
    super.key,
    required this.action,
    required this.gesture,
    required this.child,
  });
  final MessageAction action;
  final MessageMenuGesture? gesture;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (gesture == null) return child;
    return ValueListenableBuilder<MessageAction?>(
      valueListenable: gesture!.highlighted,
      builder: (context, highlighted, child) => ColoredBox(
        color: identical(highlighted, action)
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: .1)
            : Colors.transparent,
        child: child,
      ),
      child: child,
    );
  }
}

enum _Part { preview, menu, reactions }

class _MessageMenuLayout extends MultiChildLayoutDelegate {
  _MessageMenuLayout(this.anchor, this.insets);
  final Rect anchor;
  final EdgeInsets insets;

  @override
  void performLayout(Size size) {
    final area = Rect.fromLTRB(
      insets.left,
      insets.top,
      math.max(insets.left, size.width - insets.right),
      math.max(insets.top, size.height - insets.bottom),
    );
    final hasPreview = hasChild(_Part.preview);
    final hasReactions = hasChild(_Part.reactions);
    final reactionSize = hasReactions
        ? layoutChild(
            _Part.reactions,
            BoxConstraints(
              maxWidth: math.min(344, area.width),
              maxHeight: math.min(56, area.height),
            ),
          )
        : Size.zero;
    final reactionHeight = hasReactions ? reactionSize.height + 8 : 0.0;
    final menu = layoutChild(
      _Part.menu,
      BoxConstraints(
        minWidth: math.min(250, area.width),
        maxWidth: math.min(250, area.width),
        maxHeight:
            math.max(0, area.height - reactionHeight) * (hasPreview ? .7 : 1),
      ),
    );
    const gap = 8.0;
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
    final top = (anchor.top - reactionHeight)
        .clamp(area.top, math.max(area.top, area.bottom - height))
        .toDouble();
    if (hasReactions) {
      positionChild(_Part.reactions, Offset(x(reactionSize.width), top));
    }
    if (hasPreview) {
      positionChild(
        _Part.preview,
        Offset(x(preview.width), top + reactionHeight),
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
      anchor != oldDelegate.anchor || insets != oldDelegate.insets;
}

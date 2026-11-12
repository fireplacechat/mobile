import 'package:flutter/material.dart';

import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_menu_parts.dart';

/// A press that starts on a control after the menu is open.
///
/// The finger is followed with a zero-duration press: the emoji under it
/// grows, or the row under it fills, and releasing on it selects it.
class MessageHoldTracker extends StatefulWidget {
  const MessageHoldTracker({
    super.key,
    required this.onPoint,
    required this.onRelease,
    required this.child,
  });

  final ValueChanged<Offset> onPoint;
  final VoidCallback onRelease;
  final Widget child;

  @override
  State<MessageHoldTracker> createState() => _MessageHoldTrackerState();
}

class _MessageHoldTrackerState extends State<MessageHoldTracker> {
  int? _pointer;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (_pointer != null) return;
        _pointer = event.pointer;
        widget.onPoint(event.position);
      },
      onPointerMove: (event) {
        if (event.pointer != _pointer) return;
        widget.onPoint(event.position);
      },
      onPointerUp: (event) {
        if (event.pointer != _pointer) return;
        _pointer = null;
        widget.onRelease();
      },
      onPointerCancel: (event) {
        if (event.pointer != _pointer) return;
        _pointer = null;
        widget.onPoint(const Offset(double.nan, double.nan));
      },
      child: widget.child,
    );
  }
}

/// The reaction bar drawn above a held message.
class MessageReactionBar extends StatelessWidget {
  const MessageReactionBar({
    super.key,
    required this.animation,
    required this.panel,
    required this.reactions,
    required this.targets,
    required this.gesture,
    required this.onPoint,
    required this.onRelease,
    required this.onChoose,
  });

  final Animation<double> animation;
  final Color panel;
  final List<MessageAction> reactions;
  final Map<MessageAction, GlobalKey<State<StatefulWidget>>> targets;
  final MessageMenuGesture? gesture;
  final ValueChanged<Offset> onPoint;
  final VoidCallback onRelease;
  final ValueChanged<MessageAction> onChoose;

  @override
  Widget build(BuildContext context) {
    return MessageHoldTracker(
      onPoint: onPoint,
      onRelease: onRelease,
      child: Stack(
        key: const Key('messageReactionBar'),
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: const Interval(0, .5),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(MessageMenuMetrics.barHeight / 2),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x4D000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                    BoxShadow(color: Color(0x0D000000), blurRadius: 4),
                  ],
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Padding(
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
                      child: SizedBox(
                        key: targets[reaction],
                        width: MessageMenuMetrics.reactionCell,
                        height: MessageMenuMetrics.barHeight,
                        child: MessageActionHighlight(
                          action: reaction,
                          gesture: gesture,
                          lift: true,
                          child: ReactionBarButton(
                            reaction: reaction,
                            onPressed: () => onChoose(reaction),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The action list drawn under a held message.
class MessageActionsPanel extends StatelessWidget {
  const MessageActionsPanel({
    super.key,
    required this.animation,
    required this.grow,
    required this.alignEnd,
    required this.panel,
    required this.panelKey,
    required this.actions,
    required this.targets,
    required this.gesture,
    required this.onPoint,
    required this.onRelease,
    required this.onChoose,
  });

  final Animation<double> animation;
  final Animation<double> grow;
  final bool alignEnd;
  final Color panel;
  final GlobalKey panelKey;
  final List<MessageAction> actions;
  final Map<MessageAction, GlobalKey<State<StatefulWidget>>> targets;
  final MessageMenuGesture? gesture;
  final ValueChanged<Offset> onPoint;
  final VoidCallback onRelease;
  final ValueChanged<MessageAction> onChoose;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
      child: ScaleTransition(
        scale: Tween(begin: .2, end: 1.0).animate(grow),
        alignment: alignEnd ? Alignment.topRight : Alignment.topLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MessageMenuMetrics.menuRadius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 64,
                offset: Offset(0, 32),
              ),
            ],
          ),
          child: KeyedSubtree(
            key: panelKey,
            child: Material(
              key: const Key('messageActionsPanel'),
              // Solid. A translucent panel, or a blur of its own, paints the
              // bubble colour through the rows.
              color: panel,
              elevation: 0,
              shadowColor: Colors.transparent,
              borderRadius: BorderRadius.circular(
                MessageMenuMetrics.menuRadius,
              ),
              clipBehavior: Clip.antiAlias,
              child: MessageHoldTracker(
                onPoint: onPoint,
                onRelease: onRelease,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, action) in actions.indexed)
                        MessageActionHighlight(
                          key: targets[action],
                          action: action,
                          gesture: gesture,
                          child: MessageMenuRow(
                            action: action,
                            autofocus: index == 0,
                            divider: index != actions.length - 1,
                            onPressed: () => onChoose(action),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

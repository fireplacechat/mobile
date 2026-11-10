import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_actions_overlay.dart';

/// An overlay retains the initiating pointer; pushing a route would cancel it.
class MessageActionsHost extends StatefulWidget {
  const MessageActionsHost({
    super.key,
    required this.anchor,
    required this.actions,
    required this.reducedMotion,
    required this.onClosed,
    required this.onDisposed,
    this.preview,
    this.gesture,
  });
  final Rect anchor;
  final List<MessageAction> actions;
  final bool reducedMotion;
  final ValueChanged<MessageAction?> onClosed;
  final VoidCallback onDisposed;
  final Widget? preview;
  final MessageMenuGesture? gesture;
  @override
  State<MessageActionsHost> createState() => MessageActionsHostState();
}

class MessageActionsHostState extends State<MessageActionsHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: widget.reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 400),
    )..forward();
  }

  Future<void> dismiss(MessageAction? action) async {
    if (_closing) return;
    _closing = true;
    try {
      await _animation.reverse().orCancel;
      if (mounted) widget.onClosed(action);
    } on TickerCanceled {
      /* The owning overlay was disposed. */
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlockSemantics(
    child: Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: MaterialLocalizations.of(context).popupMenuLabel,
      explicitChildNodes: true,
      child: FocusScope(
        autofocus: true,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                dismiss(null),
          },
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _animation,
              curve: Curves.easeOutCubic,
            ),
            child: Stack(
              children: [
                ModalBarrier(
                  dismissible: true,
                  onDismiss: () => dismiss(null),
                  semanticsLabel: MaterialLocalizations.of(context)
                      .modalBarrierDismissLabel,
                ),
                MessageActionsOverlay(
                  anchor: widget.anchor,
                  actions: widget.actions.where((a) => !a.reaction).toList(),
                  reactions: widget.actions.where((a) => a.reaction).toList(),
                  animation: _animation,
                  preview: widget.preview,
                  gesture: widget.gesture,
                  onSelected: dismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

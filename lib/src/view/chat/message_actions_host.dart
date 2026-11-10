import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fireplace/src/view/chat/emoji_picker.dart';
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
  final void Function(MessageAction? chosen, String? emoji) onClosed;
  final VoidCallback onDisposed;
  final Widget? preview;
  final MessageMenuGesture? gesture;
  @override
  State<MessageActionsHost> createState() => MessageActionsHostState();
}

class MessageActionsHostState extends State<MessageActionsHost>
    with TickerProviderStateMixin {
  late final AnimationController _animation;
  late final AnimationController _picker;
  MessageAction? _picking;
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
    _picker = AnimationController(
      vsync: this,
      duration: widget.reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 250),
    );
  }

  /// The emoji picker replaces the reaction bar and the action list; the
  /// held message stays where it is.
  void _select(MessageAction action) {
    if (action.onEmoji == null) {
      dismiss(action);
      return;
    }
    if (_closing || _picking != null) return;
    widget.gesture?.highlighted.value = null;
    setState(() => _picking = action);
    _picker.forward();
  }

  Future<void> dismiss(MessageAction? action, [String? emoji]) async {
    if (_closing) return;
    _closing = true;
    try {
      await _animation.reverse().orCancel;
      if (mounted) widget.onClosed(action, emoji);
    } on TickerCanceled {
      /* The owning overlay was disposed. */
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _picker.dispose();
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
                gesture: _picking == null ? widget.gesture : null,
                controls: _picking == null ? null : ReverseAnimation(_picker),
                picker: CurvedAnimation(
                  parent: _picker,
                  curve: Curves.easeOutCubic,
                ),
                pickerTop:
                    (MediaQuery.sizeOf(context).height -
                        MediaQuery.viewInsetsOf(context).bottom) *
                    (1 - EmojiPickerMetrics.restingFraction),
                onSelected: _select,
                onReleased: () => dismiss(null),
              ),
              if (_picking case final picking?)
                Positioned.fill(
                  child: FadeTransition(
                    opacity: _animation,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: SlideTransition(
                        position:
                            Tween(
                              begin: const Offset(0, 1),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: _picker,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: EmojiPickerSheet(
                          recent: picking.recentEmoji,
                          onPicked: (emoji) => dismiss(picking, emoji),
                          onDismissed: () => dismiss(null),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

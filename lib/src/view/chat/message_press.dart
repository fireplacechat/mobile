import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Signal's chat long-press (`ContextMenuInteraction`).
///
/// A touch shorter than [messagePressRecognize] does nothing. At that point
/// the message eases to [messagePressScale] over [messagePressShrink]. The
/// menu opens only if the finger is still down when the shrink finishes.
/// Releasing during the shrink eases back and does not open the menu.
/// Right-click opens immediately, the same as Signal's `presentImmediately`.
const messagePressRecognize = Duration(milliseconds: 200);
const messagePressShrink = Duration(milliseconds: 200);
const messagePressScale = 0.95;

/// Press handling for one message bubble, including the shrink before focus.
class MessagePress extends StatefulWidget {
  const MessagePress({
    super.key,
    required this.child,
    this.tap,
    this.doubleTap,
    this.onReplyDelta,
    this.onReplyEnd,
    this.onReplyCancel,
    this.onFocus,
    this.onMove,
    this.onRelease,
  });

  final Widget child;
  final VoidCallback? tap;
  final VoidCallback? doubleTap;
  final ValueChanged<double>? onReplyDelta;
  final VoidCallback? onReplyEnd;
  final VoidCallback? onReplyCancel;

  /// Open the focused menu. Null when this message has no menu.
  final ValueChanged<Offset>? onFocus;
  final ValueChanged<Offset>? onMove;
  final VoidCallback? onRelease;

  @override
  State<MessagePress> createState() => _MessagePressState();
}

class _MessagePressState extends State<MessagePress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shrink;
  late final Animation<double> _scale;
  Timer? _reveal;
  bool _down = false;
  bool _opened = false;
  Offset? _origin;

  @override
  void initState() {
    super.initState();
    _shrink = AnimationController(vsync: this, duration: messagePressShrink);
    _scale = Tween<double>(
      begin: 1,
      end: messagePressScale,
    ).animate(CurvedAnimation(parent: _shrink, curve: Curves.easeInOut));
    _shrink.addStatusListener((status) {
      if (status != AnimationStatus.completed || !_down || _opened) return;
      _open();
    });
  }

  @override
  void dispose() {
    _reveal?.cancel();
    _shrink.dispose();
    super.dispose();
  }

  void _open() {
    final at = _origin;
    if (at == null || widget.onFocus == null || _opened) return;
    _opened = true;
    _reveal?.cancel();
    _shrink.value = 0;
    widget.onFocus!(at);
  }

  /// Signal presents the menu when the shrink animation finishes and the
  /// finger is still down. The same 0.2s deadline covers a hold that is
  /// pumped in one step, before the animation has ticked.
  void _armReveal() {
    _reveal?.cancel();
    _reveal = Timer(messagePressShrink, () {
      if (_down && !_opened) _open();
    });
  }

  void _start(LongPressStartDetails details) {
    _down = true;
    _opened = false;
    _origin = details.globalPosition;
    if (widget.onFocus == null) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _open();
      return;
    }
    _armReveal();
    _shrink.forward(from: 0);
  }

  void _move(LongPressMoveUpdateDetails details) {
    if (_opened) widget.onMove?.call(details.globalPosition);
  }

  void _end(LongPressEndDetails _) {
    _down = false;
    _reveal?.cancel();
    if (_opened) {
      widget.onRelease?.call();
      return;
    }
    // Signal animates back to identity over the full 0.2s, from wherever
    // the shrink had reached.
    _shrink.animateTo(0, duration: messagePressShrink, curve: Curves.easeInOut);
  }

  void _cancel() {
    _down = false;
    _reveal?.cancel();
    if (_opened || _shrink.value == 0) return;
    _shrink.animateTo(0, duration: messagePressShrink, curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final reply = widget.onReplyDelta != null;
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(duration: messagePressRecognize),
              (recognizer) {
                recognizer.onLongPressStart = widget.onFocus == null
                    ? null
                    : _start;
                recognizer.onLongPressMoveUpdate = _move;
                recognizer.onLongPressEnd = _end;
                recognizer.onLongPressCancel = _cancel;
              },
            ),
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(),
              (recognizer) {
                recognizer.onTap = widget.tap;
                recognizer.onSecondaryTapDown = widget.onFocus == null
                    ? null
                    : (details) => widget.onFocus!(details.globalPosition);
              },
            ),
        if (widget.doubleTap != null)
          DoubleTapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
                DoubleTapGestureRecognizer.new,
                (recognizer) {
                  recognizer.onDoubleTap = widget.doubleTap;
                },
              ),
        if (reply)
          HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                HorizontalDragGestureRecognizer
              >(HorizontalDragGestureRecognizer.new, (recognizer) {
                recognizer.onUpdate = (details) =>
                    widget.onReplyDelta!(details.delta.dx);
                recognizer.onEnd = (_) => widget.onReplyEnd?.call();
                recognizer.onCancel = widget.onReplyCancel;
              }),
      },
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}

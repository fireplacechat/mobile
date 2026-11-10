import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import 'package:fireplace/src/view/chat/message_actions_host.dart';

/// One extensible message action, shared by touch, desktop and accessibility.
class MessageAction {
  const MessageAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
    this.reaction = false,
    this.emoji,
    this.selected = false,
    this.onEmoji,
    this.recentEmoji = const [],
  });
  final String id, label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool destructive;
  final bool reaction, selected;
  final String? emoji;

  /// Set on the action that opens the full emoji picker inside the menu:
  /// receives the emoji chosen there. [onSelected] is then not called.
  final ValueChanged<String>? onEmoji;

  /// Emoji to offer first in that picker, newest first.
  final List<String> recentEmoji;
}

/// The original long-press recognizer keeps the pointer while the overlay opens.
/// Forward its drag/release so holding and sliding to an action also works.
class MessageMenuGesture {
  final highlighted = ValueNotifier<MessageAction?>(null);

  /// Where the finger was when the menu opened.
  Offset? origin;

  /// The finger has travelled far enough that releasing can choose a control.
  bool armed = false;

  /// A press and the control under it can both observe the same release.
  bool handled = false;

  /// A control that appears under a stationary finger must not be selected.
  static const deadZone = 40.0;

  void choose(VoidCallback action) {
    if (handled) return;
    handled = true;
    action();
  }

  bool allowsHighlight(Offset point) {
    if (armed) return true;
    final start = origin;
    if (start == null) return true;
    if ((point - start).distance < deadZone) return false;
    armed = true;
    return true;
  }

  void Function(Offset)? onMove;
  VoidCallback? onEnd, onCancel;
  void dispose() {
    onMove = null;
    onEnd = null;
    onCancel = null;
    highlighted.dispose();
  }
}

Future<void> showMessageActionsMenu(
  BuildContext context, {
  required Offset globalPosition,
  Rect? bubbleRect,
  Widget? preview,
  required List<MessageAction> actions,
  MessageMenuGesture? gesture,
}) async {
  if (actions.isEmpty || !context.mounted) return;
  // Haptics are an enhancement; platform failures must not prevent the menu.
  HapticFeedback.selectionClick().catchError((Object _) {});
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final origin = overlay.localToGlobal(Offset.zero);
  final anchor =
      (bubbleRect ?? Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0))
          .shift(-origin);
  final previousFocus = FocusManager.instance.primaryFocus;
  final reducedMotion = MediaQuery.disableAnimationsOf(context);
  final result = Completer<(MessageAction?, String?)>();
  final hostKey = GlobalKey<MessageActionsHostState>();
  late final OverlayEntry entry;
  late final LocalHistoryEntry history;
  void dismiss() => hostKey.currentState?.dismiss(null);
  history = LocalHistoryEntry(onRemove: dismiss, impliesAppBarDismissal: false);
  entry = OverlayEntry(
    builder: (ctx) => MessageActionsHost(
      key: hostKey,
      anchor: anchor,
      preview: preview,
      actions: actions,
      gesture: gesture,
      reducedMotion: reducedMotion,
      onDisposed: () {
        if (!result.isCompleted) result.complete((null, null));
      },
      onClosed: (chosen, emoji) {
        if (result.isCompleted) return;
        result.complete((chosen, emoji));
        history.remove();
        entry.remove();
        entry.dispose();
      },
    ),
  );
  ModalRoute.of(context)?.addLocalHistoryEntry(history);
  Navigator.of(context).overlay!.insert(entry);
  gesture?.origin = globalPosition;
  if (gesture != null) gesture.onCancel = dismiss;
  final (chosen, emoji) = await result.future;
  if (previousFocus?.context != null) previousFocus!.requestFocus();
  if (!context.mounted || chosen == null) return;
  if (emoji != null) {
    chosen.onEmoji?.call(emoji);
  } else {
    chosen.onSelected();
  }
}

/// Selection lives in its own sheet so it cannot compete with long-press actions.
Future<void> showSelectTextSheet(
  BuildContext context,
  String text, {
  Widget Function(BuildContext, Widget)? protectSelection,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (ctx) {
    final media = MediaQuery.of(ctx);
    final available =
        (media.size.height -
                media.viewInsets.bottom -
                media.padding.vertical -
                40)
            .clamp(0.0, media.size.height);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: available * .7),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select text',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (protectSelection == null)
                SelectableText(
                  text,
                  key: const Key('selectableMessageText'),
                  style: const TextStyle(fontSize: 17, height: 1.45),
                )
              else
                protectSelection(
                  ctx,
                  SelectableText(
                    text,
                    key: const Key('selectableMessageText'),
                    style: const TextStyle(fontSize: 17, height: 1.45),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  },
);

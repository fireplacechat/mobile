import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/ui/message_format.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';

class MessageBubble extends ConsumerStatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.senderName,
    this.actions = const [],
  });
  final LocalMessage message;

  /// Who the other person is, so a screen reader can say who sent a message. Outgoing messages are
  /// announced as "You".
  final String? senderName;

  /// Long-press menu entries. Empty means the message has no menu.
  final List<MessageAction> actions;
  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  bool _held = false; // highlighted while its menu is open
  bool _showAll = false;
  bool _focused = false;
  final _actionAnchor = GlobalKey();
  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.body != widget.message.body) {
      _showAll = false;
    }
  }

  Future<void> _openMenu(Offset at) async {
    if (widget.actions.isEmpty || _held) return;
    setState(() => _held = true);
    try {
      await showMessageActionsMenu(
        context,
        globalPosition: at,
        actions: widget.actions,
      );
    } finally {
      if (mounted) setState(() => _held = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final t = FireplaceUiTokens.of(context);
    final colors = ref.watch(chatBubbleColorsProvider);
    final mine = message.outgoing;
    final bad = message.status == MessageStatus.undecryptable;
    final fg = mine ? t.outgoingText : t.incomingText;
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(message.sentAt.toLocal()));
    // A message over the limit can only come from another client: plain text, clipped until asked.
    final oversize = !bad && messageTooLong(message.body);
    final body = oversize && !_showAll
        ? '${clipMessage(message.body, oversizedPreviewCharacters)}…'
        : message.body;
    final formatted = bad || oversize
        ? FormattedMessage([FormatRun(body, false, false, false)])
        : formatMessage(body);
    final who = mine
        ? 'You'
        : (widget.senderName == null || widget.senderName!.isEmpty
              ? 'Them'
              : widget.senderName!);
    final base = mine
        ? colors.outgoing.outgoing
        : colors.incoming.incoming(Theme.of(context).brightness);
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(mine ? 20 : 6),
      bottomRight: Radius.circular(mine ? 6 : 20),
    );
    return LayoutBuilder(
      builder: (context, box) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: FocusableActionDetector(
          enabled: widget.actions.isNotEmpty,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.f10, shift: true):
                ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.contextMenu): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                final anchor = _actionAnchor.currentContext?.findRenderObject();
                if (anchor is RenderBox) {
                  _openMenu(
                    anchor.localToGlobal(anchor.size.center(Offset.zero)),
                  );
                }
                return null;
              },
            ),
          },
          child: GestureDetector(
            key: _actionAnchor,
            // Touch: press and hold. Desktop: right click.
            onLongPressStart: widget.actions.isEmpty
                ? null
                : (d) => _openMenu(d.globalPosition),
            onSecondaryTapDown: widget.actions.isEmpty
                ? null
                : (d) => _openMenu(d.globalPosition),
            child: Container(
              key: ValueKey('messageBubble-${message.id}'),
              constraints: BoxConstraints(
                maxWidth: (box.maxWidth * .8).clamp(0.0, 480.0).toDouble(),
              ),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _held
                    ? Color.alphaBlend(const Color(0x22000000), base)
                    : base,
                borderRadius: bubbleRadius,
              ),
              // Painted over the bubble, so focus never changes its size.
              foregroundDecoration: _focused
                  ? BoxDecoration(
                      border: Border.all(color: fg, width: 2),
                      borderRadius: bubbleRadius,
                    )
                  : null,
              // The sender is announced first. The menu actions are also offered to screen readers, as
              // custom actions, because a long press is hard to perform with TalkBack or VoiceOver.
              child: Semantics(
                label: who,
                customSemanticsActions: {
                  for (final a in widget.actions)
                    CustomSemanticsAction(label: a.label): a.onSelected,
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (bad)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          children: [
                            Icon(Icons.lock_outline, size: 16, color: fg),
                            Text(
                              'Unreadable message',
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      widthFactor: 1,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text.rich(
                        formatted.span(
                          TextStyle(
                            color: fg,
                            fontSize: 16,
                            height: 1.4,
                            fontStyle: bad
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                        semanticsLabel: formatted.plain,
                      ),
                    ),
                    if (oversize)
                      TextButton(
                        key: ValueKey('showAll-${message.id}'),
                        onPressed: () => setState(() => _showAll = !_showAll),
                        child: Text(
                          _showAll ? 'Show less' : 'Show all',
                          style: TextStyle(
                            color: fg,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      time,
                      style: TextStyle(color: fg, fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

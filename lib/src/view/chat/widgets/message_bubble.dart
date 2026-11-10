import 'package:fireplace/src/view/chat/widgets/message_quote_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';

class MessageBubble extends ConsumerStatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.senderName,
    this.actions = const [],
    this.preview = false,
    this.selecting = false,
    this.selected = false,
    this.onToggleSelection,
    this.onQuote,
  });
  final LocalMessage message;
  final ValueChanged<String>? onQuote;
  final bool preview;
  final bool selecting, selected;
  final VoidCallback? onToggleSelection;

  /// Who the other person is, so a screen reader can say who sent a message. Outgoing messages are
  /// announced as "You".
  final String? senderName;

  /// Long-press menu entries. Empty means the message has no menu.
  final List<MessageAction> actions;
  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  double _replyDrag = 0;
  bool _held = false; // highlighted while its menu is open
  bool _showAll = false;
  bool _focused = false;
  final _actionAnchor = GlobalKey();
  MessageMenuGesture? _gesture;
  @override
  void dispose() {
    _gesture?.onCancel?.call();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.body != widget.message.body) {
      _showAll = false;
    }
  }

  Future<void> _openMenu(Offset at) async {
    if (widget.selecting) {
      widget.onToggleSelection?.call();
      return;
    }
    if (widget.actions.isEmpty || _held) return;
    setState(() => _held = true);
    final gesture = MessageMenuGesture();
    _gesture = gesture;
    try {
      final owner = ref.read(appSessionProvider).value;
      final anchor = _actionAnchor.currentContext?.findRenderObject();
      await showMessageActionsMenu(
        context,
        globalPosition: at,
        bubbleRect: anchor is RenderBox
            ? Rect.fromLTWH(
                anchor.localToGlobal(Offset.zero).dx,
                anchor.localToGlobal(Offset.zero).dy + 4,
                anchor.size.width,
                anchor.size.height - 8,
              )
            : null,
        preview: Consumer(
          builder: (context, previewRef, _) {
            final session = previewRef.watch(appSessionProvider).value;
            final summary = previewRef.watch(
              chatSummaryProvider(widget.message.chatId),
            );
            previewRef.watch(blockedUidsProvider);
            previewRef.watch(hiddenChatsProvider);
            previewRef.watch(identityAlertsProvider);
            final live = previewRef
                .watch(messagesProvider(widget.message.chatId))
                .value
                ?.where((m) => m.id == widget.message.id)
                .firstOrNull;
            final pending = previewRef
                .watch(pendingLocalSendsProvider)
                .values
                .any(
                  (m) =>
                      m.chatId == widget.message.chatId &&
                      m.messageId == widget.message.id,
                );
            if (!mounted ||
                !identical(session, owner) ||
                summary == null ||
                (live == null && !pending) ||
                !previewRef
                    .read(chatActivityProvider.notifier)
                    .eligible(summary)) {
              return const SizedBox.shrink();
            }
            return MessageBubble(
              message: live ?? widget.message,
              senderName: widget.senderName,
              preview: true,
            );
          },
        ),
        actions: widget.actions,
        gesture: gesture,
      );
    } finally {
      _gesture = null;
      gesture.dispose();
      if (mounted) setState(() => _held = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final reply = widget.selecting || widget.preview
        ? null
        : widget.actions.where((a) => a.id == 'reply').firstOrNull;
    final t = FireplaceUiTokens.of(context);
    final colors = ref.watch(chatBubbleColorsProvider);
    final mine = message.outgoing;
    final bad = message.status == MessageStatus.undecryptable;
    final fg = mine ? t.outgoingText : t.incomingText;
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(message.sentAt.toLocal()));
    // A message over the limit can only come from another client: plain text, clipped until asked.
    final oversize = !bad && messageTooLong(message.body);
    final body = message.remotelyDeleted
        ? 'This message was deleted'
        : oversize && !_showAll
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
                if (widget.selecting) {
                  widget.onToggleSelection?.call();
                  return null;
                }
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
            onTap: widget.selecting ? widget.onToggleSelection : null,
            onHorizontalDragUpdate: reply == null
                ? null
                : (d) => setState(
                    () => _replyDrag = (_replyDrag + d.delta.dx).clamp(0, 72),
                  ),
            onHorizontalDragCancel: () => setState(() => _replyDrag = 0),
            onHorizontalDragEnd: reply == null
                ? null
                : (_) {
                    if (_replyDrag >= 48) reply.onSelected();
                    setState(() => _replyDrag = 0);
                  },
            // Touch: press and hold. Desktop: right click.
            onLongPressStart: widget.actions.isEmpty
                ? null
                : (d) => _openMenu(d.globalPosition),
            onSecondaryTapDown: widget.actions.isEmpty
                ? null
                : (d) => _openMenu(d.globalPosition),
            onLongPressMoveUpdate: (d) =>
                _gesture?.onMove?.call(d.globalPosition),
            onLongPressEnd: (_) => _gesture?.onEnd?.call(),
            child: Opacity(
              opacity: _held ? 0 : 1,
              child: Transform.translate(
                offset: Offset(_replyDrag, 0),
                child: Container(
                  key: ValueKey(
                    '${widget.preview ? 'heldMessage' : 'messageBubble'}-${message.id}',
                  ),
                  constraints: BoxConstraints(
                    maxWidth: (box.maxWidth * (widget.preview ? 1 : .8))
                        .clamp(0.0, 480.0)
                        .toDouble(),
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
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
                    selected: widget.selecting ? widget.selected : null,
                    customSemanticsActions: {
                      for (final a
                          in widget.selecting
                              ? <MessageAction>[]
                              : widget.actions)
                        CustomSemanticsAction(label: a.label): a.onSelected,
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (message.quote != null && !message.remotelyDeleted)
                          MessageQuotePreview(
                            key: ValueKey('messageQuote-${message.id}'),
                            quote: message.quote!,
                            foreground: fg,
                            author:
                                message.quote!.senderUid ==
                                    ref.watch(
                                      appSessionProvider.select(
                                        (s) => s.value?.uid,
                                      ),
                                    )
                                ? 'You'
                                : widget.senderName ?? 'Them',
                            onTap: widget.preview
                                ? null
                                : widget.selecting
                                ? widget.onToggleSelection
                                : () => widget.onQuote?.call(
                                    message.quote!.targetId,
                                  ),
                          ),
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
                          widthFactor: message.quote == null ? 1 : null,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text.rich(
                            formatted.span(
                              TextStyle(
                                color: fg,
                                fontSize: 17,
                                height: 1.3,
                                fontStyle: bad || message.remotelyDeleted
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
                            onPressed: widget.selecting
                                ? widget.onToggleSelection
                                : () => setState(() => _showAll = !_showAll),
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
                          style: TextStyle(
                            color: mine ? fg : t.secondaryText,
                            fontSize: 11,
                            height: 1.3,
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
      ),
    );
  }
}

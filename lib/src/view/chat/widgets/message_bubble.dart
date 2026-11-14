import 'package:fireplace/src/view/chat/widgets/message_bubble_body.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:flutter/material.dart';
import 'package:fireplace/src/widgets/clock_time.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_press.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/model/chat/outgoing_sends.dart';
import 'package:fireplace/src/styles/chat_colors.dart';

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
    this.outgoingSend,
    this.onFailedTap,
    this.incomingColor,
    this.liveOf,
    this.quoteAuthor,
  });

  /// The name of whoever wrote the message this one quotes, in a group. Null
  /// in a 1:1 chat, where it is the other person.
  final String? quoteAuthor;
  final LocalMessage message;

  /// The colour of a message from someone else, when it is not this account's
  /// own choice: in a group each member's messages use that member's colour.
  final ChatBubbleColor? incomingColor;

  /// The stored message as it is now, for the copy shown while its menu is
  /// open. Set where the conversation is not a 1:1 chat (a group); null means
  /// the 1:1 history and its checks.
  final LocalMessage? Function(WidgetRef ref)? liveOf;

  /// Set for a message that is on its way or was not sent. On the way it
  /// shows its time, like a message that has been sent. A failed one says so
  /// and opens its choices when tapped.
  final OutgoingSend? outgoingSend;
  final VoidCallback? onFailedTap;
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
            if (widget.liveOf case final liveOf?) {
              final live = liveOf(previewRef);
              if (!mounted || live == null || live.remotelyDeleted) {
                return const SizedBox.shrink();
              }
              return MessageBubble(
                message: live,
                senderName: widget.senderName,
                preview: true,
                incomingColor: widget.incomingColor,
                quoteAuthor: widget.quoteAuthor,
              );
            }
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
    // A remote delete stays stored so it cannot be replayed. The row is gone.
    if (widget.message.remotelyDeleted) return const SizedBox.shrink();
    final message = widget.message;
    final reply = widget.selecting || widget.preview
        ? null
        : widget.actions.where((a) => a.id == 'reply').firstOrNull;
    final t = FireplaceUiTokens.of(context);
    final colors = ref.watch(chatBubbleColorsProvider);
    final mine = message.outgoing;
    final bad = message.status == MessageStatus.undecryptable;
    final fg = mine ? t.outgoingText : t.incomingText;
    final time = clockTime(message.sentAt, MaterialLocalizations.of(context));
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
        : (widget.incomingColor ?? colors.incoming).incoming(
            Theme.of(context).brightness,
          );
    final quoted = message.quote != null && !message.remotelyDeleted;
    // With a quote the bubble's own padding shrinks to frame the panel, so
    // the text keeps its usual distance from the edge with this.
    final textInset = quoted
        ? const EdgeInsets.symmetric(horizontal: 6)
        : EdgeInsets.zero;
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
          child: MessagePress(
            key: _actionAnchor,
            tap: widget.selecting
                ? widget.onToggleSelection
                : widget.outgoingSend?.state == OutgoingState.failed
                ? widget.onFailedTap
                : null,
            doubleTap: widget.selecting || widget.preview
                ? null
                : widget.actions
                      .where((a) => a.id == 'edit')
                      .firstOrNull
                      ?.onSelected,
            onReplyDelta: reply == null
                ? null
                : (dx) => setState(
                    () => _replyDrag = (_replyDrag + dx).clamp(0, 72),
                  ),
            onReplyCancel: reply == null
                ? null
                : () => setState(() => _replyDrag = 0),
            onReplyEnd: reply == null
                ? null
                : () {
                    if (_replyDrag >= 48) reply.onSelected();
                    setState(() => _replyDrag = 0);
                  },
            onFocus:
                widget.actions.isEmpty || widget.preview || widget.selecting
                ? null
                : _openMenu,
            onMove: (point) => _gesture?.onMove?.call(point),
            onRelease: () => _gesture?.onEnd?.call(),
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
                  margin: widget.preview
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(vertical: 4),
                  padding: quoted
                      ? const EdgeInsets.fromLTRB(8, 8, 8, 8)
                      : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _held
                        ? Color.alphaBlend(const Color(0x22000000), base)
                        : base,
                    borderRadius: bubbleRadius,
                    // The held copy is the only one drawn, so it carries the lift.
                    boxShadow: widget.preview
                        ? const [
                            BoxShadow(
                              color: Color(0x4D000000),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ]
                        : null,
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
                    // A reply is as wide as the wider of its quote and its
                    // own text; the quote panel then spans that width.
                    child: _HugWidth(
                      enabled: quoted,
                      child: MessageBubbleBody(
                        message: message,
                        senderName: widget.senderName,
                        preview: widget.preview,
                        selecting: widget.selecting,
                        quoted: quoted,
                        mine: mine,
                        bad: bad,
                        oversize: oversize,
                        showAll: _showAll,
                        formatted: formatted,
                        fg: fg,
                        base: base,
                        textInset: textInset,
                        time: time,
                        outgoingFailed:
                            widget.outgoingSend?.state == OutgoingState.failed,
                        hasOutgoingSend: widget.outgoingSend != null,
                        secondaryText: mine ? fg : t.secondaryText,
                        onToggleShowAll: () =>
                            setState(() => _showAll = !_showAll),
                        onToggleSelection: widget.onToggleSelection,
                        onQuote: widget.onQuote,
                        quoteAuthor: widget.quoteAuthor,
                      ),
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

/// Sizes a column to its widest child instead of the space offered, so that
/// children can then be stretched to that width.
class _HugWidth extends StatelessWidget {
  const _HugWidth({required this.enabled, required this.child});
  final bool enabled;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      enabled ? IntrinsicWidth(child: child) : child;
}

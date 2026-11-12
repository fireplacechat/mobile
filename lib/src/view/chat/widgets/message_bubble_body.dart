import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/view/chat/message_edit_history.dart';
import 'package:fireplace/src/view/chat/widgets/message_quote_preview.dart';

/// The quote, text and time drawn inside a [MessageBubble].
class MessageBubbleBody extends ConsumerWidget {
  const MessageBubbleBody({
    super.key,
    required this.message,
    required this.senderName,
    required this.preview,
    required this.selecting,
    required this.quoted,
    required this.mine,
    required this.bad,
    required this.oversize,
    required this.showAll,
    required this.formatted,
    required this.fg,
    required this.base,
    required this.textInset,
    required this.time,
    required this.outgoingFailed,
    required this.hasOutgoingSend,
    required this.secondaryText,
    required this.onToggleShowAll,
    this.onToggleSelection,
    this.onQuote,
  });

  final LocalMessage message;
  final String? senderName;
  final bool preview;
  final bool selecting;
  final bool quoted;
  final bool mine;
  final bool bad;
  final bool oversize;
  final bool showAll;
  final FormattedMessage formatted;
  final Color fg;
  final Color base;
  final EdgeInsets textInset;
  final String time;
  final bool outgoingFailed;
  final bool hasOutgoingSend;
  final Color secondaryText;
  final VoidCallback onToggleShowAll;
  final VoidCallback? onToggleSelection;
  final ValueChanged<String>? onQuote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: quoted
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.end,
      children: [
        if (quoted)
          MessageQuotePreview(
            key: ValueKey('messageQuote-${message.id}'),
            quote: message.quote!,
            foreground: fg,
            bubble: base,
            outgoing: mine,
            author:
                message.quote!.senderUid ==
                    ref.watch(appSessionProvider.select((s) => s.value?.uid))
                ? 'You'
                : senderName ?? 'Them',
            onTap: preview
                ? null
                : selecting
                ? onToggleSelection
                : () => onQuote?.call(message.quote!.targetId),
          ),
        if (quoted) const SizedBox(height: 5),
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
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        Padding(
          padding: textInset,
          child: Align(
            widthFactor: quoted ? null : 1,
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
        ),
        if (oversize)
          TextButton(
            key: ValueKey('showAll-${message.id}'),
            onPressed: selecting ? onToggleSelection : onToggleShowAll,
            child: Text(
              showAll ? 'Show less' : 'Show all',
              style: TextStyle(color: fg, decoration: TextDecoration.underline),
            ),
          ),
        const SizedBox(height: 2),
        Padding(
          padding: textInset,
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              if (message.edits.isNotEmpty && !message.remotelyDeleted)
                Semantics(
                  button: true,
                  label: 'View edit history',
                  child: GestureDetector(
                    key: ValueKey('edited-${message.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: preview
                        ? null
                        : selecting
                        ? onToggleSelection
                        : () => showModalBottomSheet<void>(
                            context: context,
                            useSafeArea: true,
                            showDragHandle: true,
                            builder: (_) => MessageEditHistory(
                              chatId: message.chatId,
                              messageId: message.id,
                              ownerUid:
                                  ref.read(appSessionProvider).value?.uid ?? '',
                            ),
                          ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Edited',
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ),
              if (outgoingFailed) ...[
                Icon(
                  Icons.error_outline,
                  size: MediaQuery.textScalerOf(context).scale(13),
                  color: fg,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                outgoingFailed ? 'Not sent. Tap for options.' : time,
                key: hasOutgoingSend
                    ? ValueKey('sendState-${message.id}')
                    : null,
                style: TextStyle(
                  color: secondaryText,
                  fontSize: 11,
                  height: 1.3,
                  fontWeight: outgoingFailed ? FontWeight.w700 : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

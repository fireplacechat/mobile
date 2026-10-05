import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_messages.dart';
import 'design_tokens.dart';
import 'chat_colors.dart';
import 'lockup.dart';
import 'message_format.dart';
import 'message_actions.dart';

import 'package:flutter/semantics.dart';

import '../services/message_limits.dart';

/// Enlarged titles fit normally; a nearly full-screen keyboard compacts chrome.
class UiAppBar extends AppBar {
  UiAppBar({
    super.key,
    required BuildContext context,
    Widget? title,
    super.actions,
    super.leading,
    super.centerTitle,
    double? toolbarHeight,
  }) : super(
         title:
             MediaQuery.sizeOf(context).height -
                     MediaQuery.viewInsetsOf(context).bottom <
                 160
             ? null
             : title,
         toolbarHeight: math
             .max(
               toolbarHeight ?? 64,
               MediaQuery.textScalerOf(context).scale(22) * 1.35 + 16,
             )
             .clamp(
               48,
               math.max(
                 48,
                 (MediaQuery.sizeOf(context).height -
                         MediaQuery.viewInsetsOf(context).bottom) *
                     .4,
               ),
             ),
       );
}

/// All dialog content, including actions, scrolls on short keyboard viewports.
class UiDialog extends StatelessWidget {
  const UiDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions = const [],
  });
  final Widget? icon, title, content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      backgroundColor: t.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: t.separator),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Center(child: icon!),
                const SizedBox(height: 16),
              ],
              if (title != null) ...[
                Semantics(
                  namesRoute: true,
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.headlineSmall!,
                    child: title!,
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (content != null)
                DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodyMedium!,
                  child: content!,
                ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Keep chat/search controls scroll-reachable when a keyboard leaves little space.
class UiBodyViewport extends StatelessWidget {
  const UiBodyViewport({
    super.key,
    required this.child,
    this.anchorBottom = false,
  });
  final Widget child;
  final bool anchorBottom;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxHeight >= 280) return child;
      return SingleChildScrollView(
        reverse: anchorBottom,
        child: SizedBox(
          height: math.max(
            480,
            MediaQuery.textScalerOf(context).scale(16) * 16,
          ),
          child: child,
        ),
      );
    },
  );
}

class UiStatus extends StatelessWidget {
  const UiStatus({super.key, required this.label, required this.icon});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: FireplaceUiTokens.of(context).selectedRow,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: FireplaceUiTokens.of(context).accentText, size: 20),
        const SizedBox(width: 8),
        Flexible(child: Text(label)),
      ],
    ),
  );
}

/// Constrained scrolling body for forms/settings, not the message timeline.
class UiPageScroll extends StatelessWidget {
  const UiPageScroll({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(20),
    this.maxWidth = 600,
    this.controller,
  });
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double maxWidth;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          controller: controller,
          padding: padding,
          children: children,
        ),
      ),
    ),
  );
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.size = 44});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final value = name.trim();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.selectedRow,
          border: Border.all(color: t.separator),
          borderRadius: BorderRadius.circular(size * .36),
        ),
        child: Text(
          value.isEmpty ? '?' : value.characters.first.toUpperCase(),
          style: TextStyle(color: t.text, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class UiNotice extends StatelessWidget {
  const UiNotice({
    super.key,
    required this.text,
    this.actions = const [],
    this.warning = false,
    this.brandText = false,
  });
  final String text;
  final List<Widget> actions;
  final bool warning;
  final bool brandText;
  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: warning ? t.warningSurface : t.panel,
          border: Border.all(
            color: warning ? t.warningText.withValues(alpha: .2) : t.separator,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (brandText)
              FireplaceBrandText(
                text,
                style: TextStyle(color: warning ? t.warningText : t.text),
              )
            else
              Text(
                text,
                style: TextStyle(color: warning ? t.warningText : t.text),
              ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 4, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

/// Persistent, announced feedback for an explicit action. No diagnostics or logs.
class UiActionError extends StatelessWidget {
  const UiActionError({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            color: FireplaceUiTokens.of(context).danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FireplaceBrandText(
              message,
              style: TextStyle(color: FireplaceUiTokens.of(context).danger),
            ),
          ),
        ],
      ),
    ),
  );
}

class UiEmptyState extends StatelessWidget {
  const UiEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.icon = Icons.chat_bubble_outline_rounded,
  });
  final String title, message;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: FireplaceUiTokens.of(context).selectedRow,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              icon,
              size: 36,
              color: FireplaceUiTokens.of(context).accentText,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

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

bool sameLocalDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

class DaySeparator extends StatelessWidget {
  const DaySeparator({super.key, required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        const Expanded(child: Divider()),
        const SizedBox(width: 12),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: FireplaceUiTokens.of(context).panel,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              MaterialLocalizations.of(context)
                  .formatMediumDate(date.toLocal()),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider()),
      ],
    ),
  );
}

class UiSettingsSection extends StatelessWidget {
  const UiSettingsSection({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    ),
  );
}

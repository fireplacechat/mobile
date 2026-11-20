import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/model/groups/group_selection.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_menu_parts.dart';
import 'package:fireplace/src/view/chat/message_selection_mark.dart';
import 'package:fireplace/src/view/chat/message_widgets.dart';
import 'package:fireplace/src/view/chat/timeline_scroll.dart';
import 'package:fireplace/src/view/groups/group_message_row.dart';
import 'package:fireplace/src/widgets/thin_scrollbar.dart';

/// The timeline's side padding; the jump highlight reaches back over it.
const _sideInset = MessageMenuMetrics.edge;

/// A group's messages, newest at the bottom. While messages are selected a
/// tap picks one, as in a 1:1 chat; a jump to a pinned message lights it up.
class GroupTimeline extends ConsumerStatefulWidget {
  const GroupTimeline({
    super.key,
    required this.gid,
    required this.rows,
    required this.joinedLater,
    required this.timeline,
    required this.actionsFor,
    required this.onReactions,
  });
  final String gid;
  final List<LocalMessage> rows;
  final bool joinedLater;
  final TimelineScroll timeline;
  final List<MessageAction> Function(LocalMessage) actionsFor;
  final ValueChanged<LocalMessage> onReactions;

  @override
  ConsumerState<GroupTimeline> createState() => _GroupTimelineState();
}

class _GroupTimelineState extends ConsumerState<GroupTimeline> {
  bool _loadingOlder = false;

  /// Nearing the oldest shown: load the next older messages.
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical &&
        n.metrics.extentAfter <= 800 &&
        !_loadingOlder) {
      final service = ref.read(groupServiceProvider);
      if (service != null) {
        _loadingOlder = true;
        unawaited(
          service
              .showOlderMessages(widget.gid)
              .catchError((Object _) {})
              .whenComplete(() => _loadingOlder = false),
        );
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final colors = ref.watch(groupColorsProvider(widget.gid)).value ?? const {};
    final selection = ref.watch(groupSelectionProvider(widget.gid));
    final select = ref.read(groupSelectionProvider(widget.gid).notifier);
    final theme = Theme.of(context);
    final highlight = ref
        .watch(chatBubbleColorsProvider)
        .jumpHighlight(theme.brightness, theme.scaffoldBackgroundColor);
    bool sameRun(LocalMessage a, LocalMessage? b) =>
        b != null &&
        b.status != MessageStatus.notice &&
        b.senderUid == a.senderUid &&
        sameLocalDay(a.sentAt, b.sentAt);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ThinScrollbar(
        controller: widget.timeline.controller,
        child: ListView.builder(
          key: const Key('groupMessages'),
          controller: widget.timeline.controller,
          reverse: true,
          // The same insets as a 1:1 timeline, so a held message is lifted
          // without moving.
          padding: const EdgeInsets.symmetric(
            horizontal: _sideInset,
            vertical: 12,
          ),
          itemCount: rows.length + (widget.joinedLater ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == rows.length) {
              // MLS gives a newcomer no keys for earlier messages.
              return const GroupQuietLine(
                key: Key('historyStart'),
                text: 'Messages sent before you joined aren’t shown.',
              );
            }
            final index = rows.length - 1 - i;
            final m = rows[index];
            final before = index == 0 ? null : rows[index - 1];
            final after = index == rows.length - 1 ? null : rows[index + 1];
            final showDate =
                before == null || !sameLocalDay(before.sentAt, m.sentAt);
            if (m.status == MessageStatus.notice) {
              final notice = GroupNotice.decode(m.body);
              return Column(
                key: ValueKey(m.id),
                children: [
                  if (showDate) DaySeparator(date: m.sentAt),
                  if (notice != null) GroupNoticeLine(notice: notice),
                ],
              );
            }
            final selected = selection.ids.contains(m.id);
            final row = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: selection.active ? () => select.toggle(m.id) : null,
              child: Row(
                children: [
                  if (selection.active)
                    MessageSelectionMark(selected: selected),
                  Expanded(
                    child: GroupMessageRow(
                      gid: widget.gid,
                      message: m,
                      bubbleKey: widget.timeline.anchorFor(m.id),
                      color: memberColor(colors, m.senderUid),
                      showName: !m.outgoing && !sameRun(m, before),
                      showAvatar: !m.outgoing && !sameRun(m, after),
                      actions: widget.actionsFor(m),
                      onReactions: () => widget.onReactions(m),
                      selecting: selection.active,
                      selected: selected,
                      onToggleSelection: () => select.toggle(m.id),
                    ),
                  ),
                ],
              ),
            );
            return Column(
              key: ValueKey(m.id),
              children: [
                if (showDate) DaySeparator(date: m.sentAt),
                MessageFlash(
                  messageId: m.id,
                  flashed: widget.timeline.flashed,
                  color: highlight,
                  sideInset: _sideInset,
                  child: row,
                ),
                if (m.outgoing && m.status == MessageStatus.unconfirmed)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Not confirmed',
                      key: Key('unconfirmed_${m.id}'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

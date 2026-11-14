import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/chat_composer.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_menu_parts.dart';
import 'package:fireplace/src/view/chat/message_reactions.dart';
import 'package:fireplace/src/view/chat/message_widgets.dart';
import 'package:fireplace/src/view/groups/group_info_screen.dart';
import 'package:fireplace/src/view/groups/group_message_row.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

/// A group conversation (decision 0050). It looks like a 1:1 chat: the same
/// bubbles, day separators, held-message menu, reactions and composer, with
/// editing in the composer. What differs is who is speaking: each run of
/// messages from someone else has their name above the first bubble and their
/// avatar beside the last, in that member's own colour.
class GroupChatScreen extends ConsumerStatefulWidget {
  const GroupChatScreen({super.key, required this.gid});
  final String gid;
  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final _text = TextEditingController();
  final _edit = TextEditingController();
  final _focus = FocusNode();
  LocalMessage? _editing;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _edit.addListener(_changed);
    // What is on screen has been seen: it no longer counts as unread. This
    // stays on the phone; nobody is told.
    ref.listenManual(
      groupMessagesProvider(widget.gid),
      (_, next) => _seen(next.value),
      fireImmediately: true,
    );
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _seen(List<LocalMessage>? messages) {
    final prefs = ref.read(appSessionProvider).value?.chatPreferences;
    if (prefs == null || messages == null || !prefs.available) return;
    unawaited(
      prefs
          .markSeen(groupChatId(widget.gid), [
            for (final m in messages)
              if (!m.outgoing) m.id,
          ])
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    _edit.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _error = null);
    try {
      await action();
    } on GroupActionError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'That did not go through. Try again.');
      }
    }
  }

  Future<void> _send() async {
    final service = ref.read(groupServiceProvider);
    final text = _text.text.trim();
    if (service == null || text.isEmpty) return;
    _text.clear();
    await _run(() => service.send(widget.gid, text));
  }

  void _startEdit(LocalMessage message) {
    setState(() {
      _editing = message;
      _error = null;
    });
    _edit.value = TextEditingValue(
      text: message.body,
      selection: TextSelection.collapsed(offset: message.body.length),
    );
    _focus.requestFocus();
  }

  void _cancelEdit() {
    setState(() => _editing = null);
    _edit.clear();
  }

  Future<void> _saveEdit() async {
    final service = ref.read(groupServiceProvider);
    final target = _editing;
    final body = _edit.text.trim();
    if (service == null || target == null || body.isEmpty || _busy) return;
    setState(() => _busy = true);
    await _run(() => service.edit(widget.gid, target.id, body));
    if (!mounted) return;
    setState(() => _busy = false);
    if (_error == null) _cancelEdit();
  }

  Future<void> _deleteForEveryone(LocalMessage message) async {
    final service = ref.read(groupServiceProvider);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => UiDialog(
        title: const Text('Delete for everyone?'),
        content: const Text(
          'Ask everyone’s phones to delete this message. They may already '
          'have seen or saved it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmRemoteDelete'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete for everyone',
              style: TextStyle(color: FireplaceUiTokens.of(ctx).danger),
            ),
          ),
        ],
      ),
    );
    if (!mounted || yes != true || service == null) return;
    if (_editing?.id == message.id) _cancelEdit();
    await _run(() => service.deleteForEveryone(widget.gid, message.id));
  }

  /// The held-message menu: the same controls as a 1:1 chat. Only the author
  /// can edit or delete for everyone; every phone enforces that.
  List<MessageAction> _actionsFor(LocalMessage message, String me) {
    final service = ref.read(groupServiceProvider);
    if (service == null || message.status == MessageStatus.undecryptable) {
      return const [];
    }
    void react(String emoji) =>
        unawaited(_run(() => service.react(widget.gid, message.id, emoji)));
    final sent = message.status == MessageStatus.ok;
    return [
      for (final emoji in quickReactions)
        MessageAction(
          id: 'react-$emoji',
          label: 'React with $emoji',
          icon: Icons.emoji_emotions_outlined,
          reaction: true,
          emoji: emoji,
          selected: message.reactions[me]?.emoji == emoji,
          onSelected: () => react(emoji),
        ),
      MessageAction(
        id: 'moreReactions',
        label: 'More reactions',
        icon: Icons.add,
        reaction: true,
        onEmoji: react,
        onSelected: () {},
      ),
      if (message.outgoing && sent)
        MessageAction(
          id: 'edit',
          label: 'Edit',
          icon: Icons.edit_outlined,
          onSelected: () => _startEdit(message),
        ),
      MessageAction(
        id: 'copy',
        label: 'Copy',
        icon: Icons.copy_outlined,
        onSelected: () =>
            unawaited(Clipboard.setData(ClipboardData(text: message.body))),
      ),
      if (message.outgoing && sent)
        MessageAction(
          id: 'deleteForEveryone',
          label: 'Delete for everyone',
          icon: Icons.delete_outline,
          destructive: true,
          onSelected: () => unawaited(_deleteForEveryone(message)),
        ),
      MessageAction(
        id: 'deleteForMe',
        label: 'Delete for me',
        icon: Icons.delete_sweep_outlined,
        destructive: true,
        onSelected: () => unawaited(
          _run(() => service.deleteLocally(widget.gid, message.id)),
        ),
      ),
    ];
  }

  /// Who reacted with what. Tapping your own reaction removes it.
  Future<void> _showReactions(LocalMessage message, String me) async {
    final service = ref.read(groupServiceProvider);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Reactions')),
            for (final reaction in message.reactions.entries)
              if (reaction.value.emoji case final emoji?)
                Consumer(
                  builder: (context, sheetRef, _) => ListTile(
                    leading: Text(emoji, style: const TextStyle(fontSize: 28)),
                    title: Text(
                      reaction.key == me
                          ? 'You'
                          : sheetRef
                                    .watch(peerUsernameProvider(reaction.key))
                                    .value ??
                                '…',
                    ),
                    subtitle: reaction.key == me
                        ? const Text('Tap to remove')
                        : null,
                    onTap: reaction.key == me && service != null
                        ? () {
                            Navigator.pop(ctx);
                            unawaited(
                              _run(
                                () => service.react(
                                  widget.gid,
                                  message.id,
                                  emoji,
                                ),
                              ),
                            );
                          }
                        : null,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(groupServiceProvider);
    final group = (ref.watch(groupsProvider).value ?? const {})[widget.gid];
    final me = ref.watch(appSessionProvider).value?.uid ?? '';
    final rows = [
      for (final m
          in ref.watch(groupMessagesProvider(widget.gid)).value ??
              const <LocalMessage>[])
        if (m.visible && !m.remotelyDeleted) m,
    ];
    final colors = ref.watch(groupColorsProvider(widget.gid)).value ?? const {};
    final invited =
        ref.watch(groupInvitedProvider(widget.gid)).value ?? const {};
    if (group == null || service == null) {
      return Scaffold(
        appBar: UiAppBar(context: context, title: const Text('Group')),
        body: const UiEmptyState(
          title: 'You are not in this group',
          message: 'You left it, or it was removed from this phone.',
          icon: Icons.group_off_outlined,
        ),
      );
    }
    // People who were invited and have not joined are not counted yet.
    final count = group.members
        .where((m) => !invited.containsKey(m.uid))
        .length;
    final joinedLater = service.joinedLater(widget.gid);
    final editing = _editing != null;
    bool sameRun(LocalMessage a, LocalMessage? b) =>
        b != null &&
        b.status != MessageStatus.notice &&
        b.senderUid == a.senderUid &&
        sameLocalDay(a.sentAt, b.sentAt);
    return Scaffold(
      appBar: UiAppBar(
        context: context,
        title: InkWell(
          key: const Key('groupHeader'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GroupInfoScreen(gid: widget.gid),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                '$count ${count == 1 ? 'person' : 'people'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: rows.isEmpty && !joinedLater
                ? const UiEmptyState(
                    icon: Icons.lock_outline_rounded,
                    title: 'A private group',
                    message:
                        'Messages are end-to-end encrypted. Say hello when '
                        'you’re ready.',
                  )
                : ListView.builder(
                    key: const Key('groupMessages'),
                    reverse: true,
                    // The same insets as a 1:1 timeline, so a held message is
                    // lifted without moving.
                    padding: const EdgeInsets.symmetric(
                      horizontal: MessageMenuMetrics.edge,
                      vertical: 12,
                    ),
                    itemCount: rows.length + (joinedLater ? 1 : 0),
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
                      final after = index == rows.length - 1
                          ? null
                          : rows[index + 1];
                      final showDate =
                          before == null ||
                          !sameLocalDay(before.sentAt, m.sentAt);
                      final notice = m.status == MessageStatus.notice
                          ? GroupNotice.decode(m.body)
                          : null;
                      return Column(
                        key: ValueKey(m.id),
                        children: [
                          if (showDate) DaySeparator(date: m.sentAt),
                          if (m.status == MessageStatus.notice)
                            if (notice != null) GroupNoticeLine(notice: notice),
                          if (m.status != MessageStatus.notice)
                            GroupMessageRow(
                              gid: widget.gid,
                              message: m,
                              color: memberColor(colors, m.senderUid),
                              showName: !m.outgoing && !sameRun(m, before),
                              showAvatar: !m.outgoing && !sameRun(m, after),
                              actions: _actionsFor(m, me),
                              onReactions: () => _showReactions(m, me),
                            ),
                          if (m.outgoing &&
                              m.status == MessageStatus.unconfirmed)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'Not confirmed',
                                key: Key('unconfirmed_${m.id}'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: UiActionError(
                key: const Key('groupError'),
                message: _error!,
              ),
            ),
          ChatComposer(
            keyboardInset: MediaQuery.viewInsetsOf(context).bottom,
            text: editing ? _edit : _text,
            name: group.name,
            blocked: false,
            incomingRequest: false,
            waiting: false,
            identityHeld: false,
            hasSession: true,
            contactBusy: false,
            onUnblock: () async {},
            focusNode: _focus,
            submit: editing ? _saveEdit : _send,
            editing: editing,
            editingBusy: editing && _busy,
            canSubmit: !editing || _edit.text.trim() != _editing!.body,
            contextBar: editing
                ? Row(
                    key: const Key('editComposerPreview'),
                    children: [
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 8),
                              Flexible(child: Text('Edit message')),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('cancelEdit'),
                        tooltip: 'Cancel edit',
                        onPressed: _cancelEdit,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

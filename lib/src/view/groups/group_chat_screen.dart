import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/view/chat/chat_app_bar_parts.dart';
import 'package:fireplace/src/view/chat/chat_composer.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_widgets.dart';
import 'package:fireplace/src/view/groups/group_avatar.dart';
import 'package:fireplace/src/view/groups/group_held_notice.dart';
import 'package:fireplace/src/view/groups/group_info_screen.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';
import 'package:fireplace/src/model/chat/pinned_messages.dart';
import 'package:fireplace/src/model/groups/group_selection.dart';
import 'package:fireplace/src/view/chat/pinned_bar.dart';
import 'package:fireplace/src/view/chat/timeline_scroll.dart';
import 'package:fireplace/src/view/groups/group_message_menu.dart';
import 'package:fireplace/src/model/search/message_search.dart';
import 'package:fireplace/src/view/chat/conversation_search.dart';
import 'package:fireplace/src/view/groups/group_timeline.dart';

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
  late final _timeline = TimelineScroll(isMounted: () => mounted);

  /// Search inside this group (issue 246): matches from the history on this
  /// phone.
  late final _search = ConversationSearch(
    find: (query, limit) async {
      final service = ref.read(groupServiceProvider);
      if (service == null) return const [];
      final found = await service.findMessages(
        widget.gid,
        messageMatcher(query),
        limit: limit + 1,
      );
      found.sort((a, b) => b.sentAt.compareTo(a.sentAt));
      return [for (final m in found) m.id];
    },
    jump: _openPinned,
  )..addListener(_searchChanged);

  void _searchChanged() {
    if (mounted) setState(() {});
  }

  final _text = TextEditingController();
  final _edit = TextEditingController();
  final _focus = FocusNode();
  LocalMessage? _editing;
  LocalMessage? _replyTo;
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
    final service = ref.read(groupServiceProvider);
    if (prefs == null ||
        service == null ||
        messages == null ||
        !prefs.available ||
        // Nothing unseen: nothing to write.
        ref.read(groupUnreadProvider(widget.gid)) == 0) {
      return;
    }
    unawaited(() async {
      try {
        await service.markRead(widget.gid, [
          for (final m in messages)
            if (!m.outgoing) m.id,
        ]);
        if (mounted) ref.invalidate(groupUnreadCountProvider(widget.gid));
      } catch (_) {
        // The count stays; it is tried again with the next message.
      }
    }());
  }

  @override
  void dispose() {
    _text.dispose();
    _edit.dispose();
    _focus.dispose();
    _timeline.dispose();
    _search.dispose();
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
    final replyTo = _replyTo;
    _text.clear();
    setState(() => _replyTo = null);
    await _run(() => service.send(widget.gid, text, replyTo: replyTo));
  }

  void _startReply(LocalMessage message) {
    setState(() {
      _replyTo = message;
      _editing = null;
      _error = null;
    });
    _focus.requestFocus();
  }

  void _startEdit(LocalMessage message) {
    setState(() {
      _editing = message;
      _replyTo = null;
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

  void _notice(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Messages about to be deleted are no longer edited or quoted.
  void _letGo(Set<String> ids) {
    if (ids.contains(_editing?.id)) _cancelEdit();
    if (ids.contains(_replyTo?.id)) setState(() => _replyTo = null);
  }

  List<MessageAction> _actionsFor(LocalMessage message, String me) {
    final service = ref.read(groupServiceProvider);
    if (service == null) return const [];
    return groupMessageActions(
      message,
      gid: widget.gid,
      me: me,
      ref: ref,
      context: context,
      isMounted: () => mounted,
      notice: _notice,
      run: _run,
      onReact: (emoji) =>
          unawaited(_run(() => service.react(widget.gid, message.id, emoji))),
      onReply: () => _startReply(message),
      onEdit: () => _startEdit(message),
      onDeleting: () => _letGo({message.id}),
    );
  }

  /// Opens a pinned message or a search match: loads the history back to it,
  /// then scrolls to it and lights it up, as a 1:1 chat does.
  Future<void> _openPinned(String id) async {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    try {
      await ref.read(groupServiceProvider)?.revealMessage(widget.gid, id);
    } catch (_) {
      // Not found: nothing to scroll to.
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final ids = [
      for (final m
          in ref.read(groupMessagesProvider(widget.gid)).value ??
              const <LocalMessage>[])
        if (m.visible && !m.remotelyDeleted) m.id,
    ];
    final found = await _timeline.locate(id, ids, reduceMotion: reduceMotion);
    if (found && mounted) _timeline.flash(id);
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
    final joinedLater = service.joinedLater(widget.gid);
    final editing = _editing != null;
    // The message being replied to, as it is now: it may have been edited or
    // deleted since.
    final replyTo = _replyTo == null
        ? null
        : rows.where((m) => m.id == _replyTo!.id).firstOrNull;
    final brightness = Theme.of(context).brightness;
    final selection = ref.watch(groupSelectionProvider(widget.gid));
    final selecting = selection.active;
    final select = ref.read(groupSelectionProvider(widget.gid).notifier);
    final pinned = [
      for (final id
          in ref.watch(pinnedMessagesProvider)[groupChatId(widget.gid)] ??
              const <String>[])
        // A pinned message may be older than the loaded history.
        ?(rows.where((m) => m.id == id).firstOrNull ??
            ref.watch(groupStoredMessageProvider((widget.gid, id))).value),
    ];
    // Laid out as a 1:1 chat's title (issue 210): the avatar, then the name
    // at the size of a name in the chat list.
    final title = Row(
      children: [
        GroupAvatar(name: group.name, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            key: const Key('groupHeader'),
            onTap: selecting
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GroupInfoScreen(
                        gid: widget.gid,
                        onSearch: _search.open,
                      ),
                    ),
                  ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ChatTitleName(group.name),
            ),
          ),
        ),
      ],
    );
    final searching = _search.active;
    return PopScope(
      canPop: !selecting && !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        searching ? _search.close() : select.clear();
      },
      child: Scaffold(
        appBar: selecting
            // Selecting, as in a 1:1 chat (issue 209).
            ? UiAppBar(
                context: context,
                toolbarHeight: 64,
                leading: TextButton(
                  key: const Key('deleteAllMessages'),
                  onPressed: selection.deleting
                      ? null
                      : () => deleteAllGroupMessages(
                          context,
                          ref,
                          widget.gid,
                          onDeleting: _letGo,
                        ),
                  child: const Text('Delete All'),
                ),
                leadingWidth: 120,
                title: title,
                actions: [
                  TextButton(
                    key: const Key('exitMessageSelection'),
                    onPressed: selection.deleting ? null : select.clear,
                    child: const Text('Cancel'),
                  ),
                ],
              )
            : searching
            ? UiAppBar(
                context: context,
                toolbarHeight: 64,
                leading: ConversationSearchClose(search: _search),
                title: ConversationSearchField(search: _search),
                actions: [ConversationSearchControls(search: _search)],
              )
            : UiAppBar(context: context, toolbarHeight: 64, title: title),
        bottomNavigationBar: selecting
            ? GroupSelectionBar(gid: widget.gid, onDeleting: _letGo)
            : null,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: selecting ? select.clear : null,
          child: Column(
            children: [
              GroupHeldNotice(gid: widget.gid),
              if (pinned.isNotEmpty)
                PinnedBar(messages: pinned, onOpen: _openPinned),
              Expanded(
                child: rows.isEmpty && !joinedLater
                    ? const UiEmptyState(
                        icon: Icons.lock_outline_rounded,
                        title: 'A private group',
                        message:
                            'Messages are end-to-end encrypted. Say hello when '
                            'you’re ready.',
                      )
                    : SearchHighlight(
                        query: searching ? _search.query : '',
                        child: GroupTimeline(
                          gid: widget.gid,
                          rows: rows,
                          joinedLater: joinedLater,
                          timeline: _timeline,
                          actionsFor: (m) => _actionsFor(m, me),
                          onReactions: (m) => _showReactions(m, me),
                        ),
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
              if (!selecting)
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
                      : _replyTo != null
                      ? Consumer(
                          builder: (context, barRef, _) => ReplyPanel(
                            key: const Key('replyComposerPreview'),
                            author: _replyTo!.outgoing
                                ? 'You'
                                : barRef
                                          .watch(
                                            peerUsernameProvider(
                                              _replyTo!.senderUid,
                                            ),
                                          )
                                          .value ??
                                      '…',
                            body: clipMessage(replyTo?.body ?? '', 1024),
                            unavailable: replyTo == null,
                            // The colour of the person replied to: their own in
                            // this group, or this account's primary colour.
                            color:
                                (_replyTo!.outgoing
                                        ? barRef
                                              .watch(chatBubbleColorsProvider)
                                              .outgoing
                                        : memberColor(
                                            colors,
                                            _replyTo!.senderUid,
                                          ))
                                    .accentText(brightness),
                            onCancel: () => setState(() => _replyTo = null),
                          ),
                        )
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

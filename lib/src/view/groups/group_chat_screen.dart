import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/groups/group_info_screen.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:fireplace/src/widgets/clock_time.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// A group conversation (decision 0050). Each run of messages from one person
/// has their name above the first bubble and their avatar beside the last;
/// other members' bubbles use the soft version of their own primary colour.
class GroupChatScreen extends ConsumerStatefulWidget {
  const GroupChatScreen({super.key, required this.gid});
  final String gid;
  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
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
    if (service == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _text.clear();
    await _run(() => service.send(widget.gid, text));
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _actions(LocalMessage m, bool mine) async {
    final service = ref.read(groupServiceProvider);
    if (service == null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final e in _quickReactions)
                    TextButton(
                      key: Key('react_$e'),
                      onPressed: () => Navigator.pop(ctx, 'react:$e'),
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                ],
              ),
            ),
            if (mine)
              ListTile(
                key: const Key('editGroupMessage'),
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
            if (mine)
              ListTile(
                key: const Key('deleteForEveryone'),
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete for everyone'),
                onTap: () => Navigator.pop(ctx, 'deleteAll'),
              ),
            ListTile(
              key: const Key('deleteForMe'),
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Delete for me'),
              onTap: () => Navigator.pop(ctx, 'deleteMine'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice.startsWith('react:')) {
      await _run(() => service.react(widget.gid, m.id, choice.substring(6)));
    } else if (choice == 'edit') {
      final controller = TextEditingController(text: m.body);
      final body = await showDialog<String>(
        context: context,
        builder: (ctx) => UiDialog(
          title: const Text('Edit message'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('saveEdit'),
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (body != null) await _run(() => service.edit(widget.gid, m.id, body));
    } else if (choice == 'deleteAll') {
      await _run(() => service.deleteForEveryone(widget.gid, m.id));
    } else if (choice == 'deleteMine') {
      await _run(() => service.deleteLocally(widget.gid, m.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider).value ?? const {};
    final group = groups[widget.gid];
    final me = ref.watch(appSessionProvider).value?.uid ?? '';
    final messages = [
      for (final m
          in ref.watch(groupMessagesProvider(widget.gid)).value ??
              const <LocalMessage>[])
        if (m.visible && !m.remotelyDeleted) m,
    ];
    final colors = ref.watch(groupColorsProvider(widget.gid)).value ?? const {};
    if (group == null) {
      return Scaffold(
        appBar: UiAppBar(context: context, title: const Text('Group')),
        body: const UiEmptyState(
          title: 'You are not in this group',
          message: 'You left it, or it was removed from this phone.',
          icon: Icons.group_off_outlined,
        ),
      );
    }
    final count = group.members.length;
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
            child: messages.isEmpty
                ? const UiEmptyState(
                    title: 'Say hello',
                    message: 'Messages in this group are end-to-end encrypted.',
                    icon: Icons.forum_outlined,
                  )
                : ListView.builder(
                    key: const Key('groupMessages'),
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final index = messages.length - 1 - i;
                      final m = messages[index];
                      final mine = m.senderUid == me;
                      final first =
                          index == 0 ||
                          messages[index - 1].senderUid != m.senderUid;
                      final last =
                          index == messages.length - 1 ||
                          messages[index + 1].senderUid != m.senderUid;
                      return GroupBubble(
                        message: m,
                        mine: mine,
                        showName: first && !mine,
                        showAvatar: last && !mine,
                        color:
                            ChatBubbleColor.values
                                .asNameMap()[colors[m.senderUid]] ??
                            ChatBubbleColor.stone,
                        onHold: () => _actions(m, mine),
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('groupComposer'),
                      controller: _text,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'Message'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    key: const Key('groupSend'),
                    tooltip: 'Send',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One message in a group. Reused for every row.
class GroupBubble extends ConsumerWidget {
  const GroupBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.showName,
    required this.showAvatar,
    required this.color,
    required this.onHold,
  });
  final LocalMessage message;
  final bool mine, showName, showAvatar;
  final ChatBubbleColor color;
  final VoidCallback onHold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = FireplaceUiTokens.of(context);
    final brightness = Theme.of(context).brightness;
    final name = mine
        ? 'You'
        : ref.watch(peerUsernameProvider(message.senderUid)).value ?? '…';
    final background = mine ? t.outgoingBubble : color.incoming(brightness);
    final foreground = mine ? t.outgoingText : t.incomingText;
    final reactions = message.reactions.values.map((r) => r.emoji).toList();
    final bubble = GestureDetector(
      onLongPress: onHold,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.body, style: TextStyle(color: foreground)),
            const SizedBox(height: 2),
            Text(
              [
                clockTime(message.sentAt, MaterialLocalizations.of(context)),
                if (message.editClock > 0) 'edited',
                if (message.status == MessageStatus.unconfirmed)
                  'not confirmed',
              ].join(' · '),
              style: TextStyle(
                color: foreground.withValues(alpha: .7),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: showName ? 10 : 2),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (showName)
            Padding(
              padding: const EdgeInsets.only(left: 44, bottom: 2),
              child: Text(
                name,
                style: TextStyle(
                  color: color.accentText(brightness),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: mine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine)
                SizedBox(
                  width: 36,
                  child: showAvatar ? PersonAvatar(name: name, size: 30) : null,
                ),
              if (!mine) const SizedBox(width: 8),
              Flexible(child: bubble),
            ],
          ),
          if (reactions.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: mine ? 0 : 44, top: 2),
              child: Text(
                reactions.join(' '),
                key: Key('reactions_${message.id}'),
              ),
            ),
        ],
      ),
    );
  }
}

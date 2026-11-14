import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/view/groups/contact_picker.dart';
import 'package:fireplace/src/view/groups/group_avatar.dart';
import 'package:fireplace/src/view/groups/text_prompt_dialog.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

/// A group's members and settings. Any member may invite people they chat
/// with; administrators rename the group and remove people; anyone may leave.
class GroupInfoScreen extends ConsumerStatefulWidget {
  const GroupInfoScreen({super.key, required this.gid});
  final String gid;
  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on GroupRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on GroupActionError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'That did not go through. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => UiDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('confirmGroupAction'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _rename(GroupInfo group) async {
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: 'Rename group',
        initial: group.name,
        maxLength: GroupLimits.maxNameChars,
        fieldKey: const Key('renameField'),
        saveKey: const Key('saveRename'),
      ),
    );
    final name = entered?.trim();
    final service = ref.read(groupServiceProvider);
    if (name == null || name.isEmpty || name == group.name || service == null) {
      return;
    }
    await _run(() => service.rename(widget.gid, name));
  }

  Future<void> _addPeople(GroupInfo group) async {
    final service = ref.read(groupServiceProvider);
    if (service == null) return;
    final inGroup = {for (final m in group.members) m.uid};
    final picked = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => _AddPeopleScreen(
          exclude: inGroup,
          room: GroupLimits.maxMembers - inGroup.length,
        ),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    await _run(() async {
      for (final uid in picked) {
        await service.invite(widget.gid, uid);
      }
    });
    if (mounted && _error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            picked.length == 1
                ? 'Invitation sent.'
                : '${picked.length} invitations sent.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(groupServiceProvider);
    final group = (ref.watch(groupsProvider).value ?? const {})[widget.gid];
    final me = ref.watch(appSessionProvider).value?.uid ?? '';
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
    final admin = group.isAdmin(me);
    final members = [...group.members]
      ..sort((a, b) => (a.uid == me ? 0 : 1).compareTo(b.uid == me ? 0 : 1));
    return Scaffold(
      appBar: UiAppBar(context: context, title: const Text('Group info')),
      body: UiPageScroll(
        children: [
          const SizedBox(height: 16),
          Center(child: GroupAvatar(name: group.name, size: 72)),
          const SizedBox(height: 12),
          Center(
            child: Text(
              group.name,
              key: const Key('groupInfoName'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Center(
            child: Text(
              '${members.length} of ${GroupLimits.maxMembers} people',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: UiActionError(message: _error!),
            ),
          const SizedBox(height: 8),
          if (members.length < GroupLimits.maxMembers)
            ListTile(
              key: const Key('addPeople'),
              enabled: !_busy,
              leading: const Icon(Icons.person_add_alt_outlined),
              title: const Text('Add people'),
              subtitle: const Text('They join once they accept'),
              onTap: () => _addPeople(group),
            ),
          if (admin)
            ListTile(
              key: const Key('renameGroup'),
              enabled: !_busy,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename group'),
              onTap: () => _rename(group),
            ),
          const Divider(),
          for (final m in members)
            _MemberRow(
              member: m,
              me: m.uid == me,
              canRemove: admin && m.uid != me && !_busy,
              onRemove: (name) async {
                if (await _confirm(
                  'Remove @$name?',
                  'They will no longer receive messages in this group.',
                  'Remove',
                )) {
                  await _run(() => service.remove(widget.gid, m.uid));
                }
              },
            ),
          const Divider(),
          ListTile(
            key: const Key('leaveGroup'),
            enabled: !_busy,
            leading: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Leave group',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: Text(
              members.length == 1
                  ? 'You are the last member, so the group ends.'
                  : 'Your copy of past messages stays on this phone.',
            ),
            onTap: () async {
              final navigator = Navigator.of(context);
              if (!await _confirm(
                'Leave ${group.name}?',
                'You will stop receiving its messages. Someone can invite '
                    'you again later.',
                'Leave',
              )) {
                return;
              }
              await _run(() => service.leave(widget.gid));
              if (mounted && _error == null) {
                navigator.popUntil((r) => r.isFirst);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// One person in the member list.
class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.member,
    required this.me,
    required this.canRemove,
    required this.onRemove,
  });
  final GroupMember member;
  final bool me, canRemove;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(peerUsernameProvider(member.uid)).value ?? '…';
    return ListTile(
      key: Key('member_${member.uid}'),
      leading: PersonAvatar(name: name, size: 40),
      title: Text(me ? 'You' : '@$name'),
      subtitle: member.admin ? const Text('Administrator') : null,
      trailing: canRemove
          ? IconButton(
              key: Key('remove_${member.uid}'),
              tooltip: 'Remove from group',
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: () => onRemove(name),
            )
          : null,
    );
  }
}

/// Picks contacts to invite into an existing group.
class _AddPeopleScreen extends ConsumerStatefulWidget {
  const _AddPeopleScreen({required this.exclude, required this.room});
  final Set<String> exclude;
  final int room;
  @override
  ConsumerState<_AddPeopleScreen> createState() => _AddPeopleScreenState();
}

class _AddPeopleScreenState extends ConsumerState<_AddPeopleScreen> {
  Set<String> _picked = const {};

  @override
  Widget build(BuildContext context) {
    final contacts = [
      for (final uid in ref.watch(groupContactsProvider))
        if (!widget.exclude.contains(uid)) uid,
    ];
    return Scaffold(
      appBar: UiAppBar(
        context: context,
        title: const Text('Add people'),
        actions: [
          TextButton(
            key: const Key('sendInvites'),
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.pop(context, _picked),
            child: const Text('Invite'),
          ),
        ],
      ),
      body: contacts.isEmpty
          ? const UiEmptyState(
              title: 'No one else to invite',
              message: 'Everyone you chat with is already here.',
              icon: Icons.group_outlined,
            )
          : UiPageScroll(
              children: [
                ContactPicker(
                  contacts: contacts,
                  selected: _picked,
                  limit: widget.room,
                  onChanged: (s) => setState(() => _picked = s),
                ),
              ],
            ),
    );
  }
}

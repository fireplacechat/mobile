import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/view/groups/group_avatar.dart';
import 'package:fireplace/src/widgets/status.dart';

/// An invitation to a group, with Join and Decline. The group's name is
/// encrypted for its members, so it shows once you have joined.
class GroupInvitationCard extends ConsumerStatefulWidget {
  const GroupInvitationCard({super.key, required this.invitation});
  final GroupInvitation invitation;
  @override
  ConsumerState<GroupInvitationCard> createState() =>
      _GroupInvitationCardState();
}

class _GroupInvitationCardState extends ConsumerState<GroupInvitationCard> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function(String gid) action) async {
    final service = ref.read(groupServiceProvider);
    if (service == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(widget.invitation.gid);
    } on GroupRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on GroupActionError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not answer this invitation. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(groupServiceProvider);
    final inviter =
        ref.watch(peerUsernameProvider(widget.invitation.inviter)).value ?? '…';
    return Card(
      key: Key('groupInvite_${widget.invitation.gid}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const GroupAvatar(name: '', size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '@$inviter invited you to a group',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'If you join, everyone in the group can read what you send '
              'there. You can leave at any time.',
            ),
            if (_error != null) UiActionError(message: _error!),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('declineGroup'),
                  onPressed: _busy || service == null
                      ? null
                      : () => _run(service.decline),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('joinGroup'),
                  onPressed: _busy || service == null
                      ? null
                      : () => _run(service.accept),
                  child: const Text('Join'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

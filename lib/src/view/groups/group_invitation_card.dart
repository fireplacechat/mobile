import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:fireplace/src/view/groups/group_chat_screen.dart';
import 'package:fireplace/src/widgets/status.dart';

/// An invitation to a group, with Join and Decline. The group's name is
/// encrypted for its members, so it shows once you have joined.
///
/// Shown in Message requests and in the 1:1 chat with the person who sent
/// it; answering it in one place takes it away from both.
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
    // The card's own look, with the slightly rounded corners of the invite
    // tickets and theme previews.
    final cardShape = Theme.of(context).cardTheme.shape;
    return Card(
      key: Key('groupInvite_${widget.invitation.gid}'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: cardShape is RoundedRectangleBorder
            ? cardShape.side
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // The person who invited, as everywhere else: their initial
                // in their colour.
                PersonAvatar(
                  name: inviter,
                  size: 40,
                  color: ref
                      .watch(knownPeerColorProvider(widget.invitation.inviter))
                      ?.outgoing,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$inviter invited you to a group',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (_error != null) UiActionError(message: _error!),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('declineGroup'),
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: _busy || service == null
                      ? null
                      : () => _run(service.decline),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('joinGroup'),
                  // Slightly rounded, as the invite tickets and theme
                  // previews are.
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: _busy || service == null
                      ? null
                      : () async {
                          // Joining takes the card away, so keep what opening
                          // the group needs.
                          final navigator = Navigator.of(context);
                          final gid = widget.invitation.gid;
                          var joined = false;
                          await _run((g) async {
                            await service.accept(g);
                            joined = true;
                          });
                          if (!joined) return;
                          // Straight into the conversation, as the owner asked.
                          unawaited(
                            navigator.push(
                              MaterialPageRoute<void>(
                                builder: (_) => GroupChatScreen(gid: gid),
                              ),
                            ),
                          );
                        },
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

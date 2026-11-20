import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/model/groups/group_service.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/view/chat/review_chat_identity.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:fireplace/src/view/groups/group_chat_screen.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/safety/request_buttons.dart';
import 'package:fireplace/src/widgets/status.dart';

/// An invitation to a group, with Join and Decline. The group's name is
/// encrypted for its members, so it shows once you have joined.
///
/// Shown in Message requests and in the 1:1 chat with the person who sent
/// it; answering it in one place takes it away from both.
class GroupInvitationCard extends ConsumerStatefulWidget {
  const GroupInvitationCard({
    super.key,
    required this.invitation,
    this.inRequests = false,
  });

  /// On Message requests: drawn as one of its rows (issue 248), and Join
  /// takes that page's place, so Back leads to the chat list (issue 243).
  final bool inRequests;
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
    } on IdentityChangedException catch (e) {
      // A member's security code is not the one this phone knows. Joining
      // waits until the person has looked at it.
      if (!mounted) return;
      final session = ref.read(appSessionProvider).value;
      if (session == null) return;
      await reviewChatIdentity(
        context,
        session,
        e.peerUid,
        e.newIdentityPub,
        isMounted: () => mounted,
        notice: (_) {},
      );
      if (mounted) {
        setState(
          () => _error = 'A member’s security code changed. Join again.',
        );
      }
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
    final row = widget.inRequests;
    // The person who invited, as everywhere else: their initial in their
    // colour.
    final avatar = PersonAvatar(
      name: inviter,
      size: row ? 52 : 40,
      color: ref
          .watch(knownPeerColorProvider(widget.invitation.inviter))
          ?.outgoing,
    );
    final decline = row
        ? OutlinedButton(
            key: const Key('declineGroup'),
            style: RequestButtons.quiet(context),
            onPressed: _busy || service == null
                ? null
                : () => _run(service.decline),
            child: const Text('Decline'),
          )
        : TextButton(
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
          );
    final join = FilledButton(
      key: const Key('joinGroup'),
      // In a chat, slightly rounded, as the invite tickets and theme
      // previews are.
      style: row
          ? RequestButtons.main()
          : FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
      onPressed: _busy || service == null ? null : () => _join(service),
      child: const Text('Join'),
    );
    if (row) {
      final t = FireplaceUiTokens.of(context);
      return Padding(
        key: Key('groupInvite_${widget.invitation.gid}'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Their face, marked as a group invitation.
            Stack(
              clipBehavior: Clip.none,
              children: [
                avatar,
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: t.page,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.group, size: 14, color: t.accentText),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$inviter invited you to a group',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Join to see its name and messages.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.33,
                      color: t.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [join, decline]),
                  if (_error != null) UiActionError(message: _error!),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
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
                avatar,
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
              children: [decline, const SizedBox(width: 8), join],
            ),
          ],
        ),
      ),
    );
  }

  /// Straight into the group once joined, as the owner asked.
  Future<void> _join(GroupService service) async {
    // Joining takes the invitation away, so keep what opening the group
    // needs.
    final navigator = Navigator.of(context);
    final gid = widget.invitation.gid;
    final origin = ModalRoute.of(context);
    final replace = widget.inRequests;
    // Opened as the chat list opens a group.
    final destination = MaterialPageRoute<void>(
      builder: (_) => GroupChatScreen(gid: gid),
    );
    var joined = false;
    await _run((g) async {
      await service.accept(g);
      joined = true;
    });
    if (!joined || !navigator.mounted || origin?.isCurrent != true) return;
    unawaited(
      replace
          ? navigator.pushReplacement(destination)
          : navigator.push(destination),
    );
  }
}

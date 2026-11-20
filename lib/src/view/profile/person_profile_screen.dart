import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/chat_safety_actions.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/safety/confirm_block.dart';
import 'package:fireplace/src/view/safety/report_spam.dart';
import 'package:fireplace/src/view/safety/verify_screen.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/settings_section.dart';
import 'package:fireplace/src/widgets/status.dart';
import 'package:fireplace/src/widgets/round_bubble_icon.dart';

/// What the 1:1 chat hands its profile, so the chat's own handling (going
/// home after a block, its notices) applies; Message then goes back to it.
@immutable
class ProfileChatHandlers {
  const ProfileChatHandlers({
    required this.chatId,
    required this.onMute,
    required this.onBlock,
    required this.onUnblock,
    required this.onReportSpam,
    this.onSearch,
  });
  final String chatId;

  /// Opens the search inside that chat (issue 246).
  final VoidCallback? onSearch;
  final Future<void> Function(bool muted) onMute;
  final Future<void> Function() onBlock, onUnblock;
  final Future<void> Function(ReportSpamChoice choice) onReportSpam;
}

/// The group whose member list opened the profile. Whether they administer
/// it, and whether you may change that, are read live from the group, so the
/// page follows a change made here or on another phone (issue 244).
@immutable
class ProfileGroupMember {
  const ProfileGroupMember({
    required this.gid,
    required this.onRole,
    required this.confirmRemove,
    required this.onRemove,
  });
  final String gid;
  final Future<void> Function(bool admin) onRole;

  /// Asks before removing them; true to go ahead.
  final Future<bool> Function() confirmRemove;
  final Future<void> Function() onRemove;
}

/// One person: who they are, a way to message them, their security code and
/// the safety actions. The same page whether it is opened from your chat with
/// them or from a group's member list, where you may never have chatted
/// (issue 244). It shows nothing the phone does not already have.
class PersonProfileScreen extends ConsumerStatefulWidget {
  const PersonProfileScreen({
    super.key,
    required this.peerUid,
    required this.name,
    this.color,
    this.inChat,
    this.member,
  });
  final String peerUid, name;

  /// Their avatar colour where the opener knows it (a group's member list).
  final Color? color;
  final ProfileChatHandlers? inChat;
  final ProfileGroupMember? member;
  @override
  ConsumerState<PersonProfileScreen> createState() =>
      _PersonProfileScreenState();
}

class _PersonProfileScreenState extends ConsumerState<PersonProfileScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _run(
    Future<void> Function() action, {
    String failure = 'Could not update this contact. Try again.',
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Back to the chat it came from; otherwise into your chat with them,
  /// started the same way as from New chat when there is none yet.
  Future<void> _message(String? chatId) async {
    final navigator = Navigator.of(context);
    if (widget.inChat != null) {
      navigator.pop();
      return;
    }
    void open(String id) => navigator.push(
      MaterialPageRoute<void>(builder: (_) => ChatScreen(chatId: id)),
    );
    if (chatId != null) {
      open(chatId);
      return;
    }
    final session = ref.read(appSessionProvider).value;
    if (session == null) return;
    await _run(() async {
      final id = await session.chat.startChat(widget.name);
      if (mounted) open(id);
    }, failure: 'Could not start chat. Try again.');
  }

  Future<void> _block(bool blocked) async {
    if (_busy) return;
    final session = ref.read(appSessionProvider).value;
    final chat = widget.inChat;
    if (!blocked) {
      final ok = await confirmBlock(context, widget.name);
      if (!ok || !mounted) return;
    }
    await _run(() async {
      if (chat != null) {
        await (blocked ? chat.onUnblock() : chat.onBlock());
      } else if (session != null) {
        await (blocked
            ? session.safety.unblock(widget.peerUid)
            : session.safety.block(widget.peerUid));
      }
    });
  }

  Future<void> _report(bool blocked) async {
    if (_busy) return;
    final choice = await confirmReportSpam(context, blocked: blocked);
    if (choice == null || !mounted) return;
    final session = ref.read(appSessionProvider).value;
    final chat = widget.inChat;
    await _run(() async {
      if (chat != null) {
        await chat.onReportSpam(choice);
      } else if (session != null) {
        await reportSpam(
          context,
          session,
          widget.peerUid,
          choice,
          notice: _notice,
        );
      }
    }, failure: 'Could not send the spam report. Try again.');
  }

  Future<void> _mute(String chatId, bool muted) => _run(() async {
    final chat = widget.inChat;
    if (chat != null) {
      await chat.onMute(muted);
    } else {
      await ref.read(chatActivityProvider.notifier).mute(chatId, muted);
    }
  }, failure: 'Could not save the mute preference. Try again.');

  Future<void> _remove(ProfileGroupMember member) async {
    if (_busy) return;
    final navigator = Navigator.of(context);
    if (!await member.confirmRemove() || !mounted) return;
    var removed = false;
    await _run(() async {
      await member.onRemove();
      removed = true;
    });
    if (removed && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final me = ref.watch(appSessionProvider).value?.uid;
    // Your chat with them, if there is one: the chat list's own record.
    final ownId = me == null ? null : ChatService.chatIdFor(me, w.peerUid);
    final known =
        ownId != null && ref.watch(chatSummaryProvider(ownId)) != null;
    final chatId = w.inChat?.chatId ?? (known ? ownId : null);
    final verified = ref.watch(peerVerifiedProvider(w.peerUid)).value == true;
    final blocked =
        ref.watch(blockedUidsProvider).value?.contains(w.peerUid) == true;
    final muted =
        chatId != null &&
        ref.watch(chatActivityProvider.select((s) => s.muted.contains(chatId)));
    final member = w.member;
    // Their place in that group, as Group info counts it: people still
    // invited are not members yet, and with no administrator named,
    // everybody administers.
    final group = member == null
        ? null
        : (ref.watch(groupsProvider).value ?? const {})[member.gid];
    final invited = member == null
        ? const <String, String>{}
        : ref.watch(groupInvitedProvider(member.gid)).value ?? const {};
    final present = [
      for (final m in group?.members ?? const <GroupMember>[])
        if (!invited.containsKey(m.uid)) m,
    ];
    final inGroup = present.where((m) => m.uid == w.peerUid).firstOrNull;
    final isAdmin =
        inGroup != null && (inGroup.admin || !present.any((m) => m.admin));
    final canManage =
        inGroup != null && me != null && group!.isAdmin(me) && me != w.peerUid;
    final named = w.name.isNotEmpty && w.name != '…';
    return Scaffold(
      appBar: UiAppBar(context: context, title: const Text('Profile')),
      body: UiPageScroll(
        children: [
          Center(
            child: PersonAvatar(
              name: w.name,
              size: 88,
              color:
                  w.color ??
                  ref.watch(acceptedPeerColorProvider(w.peerUid))?.outgoing,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            w.name,
            key: const Key('profileName'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Group administrator',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 20),
          // Equal tiles, as wide as the page allows up to a phone's width.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Row(
                children: [
                  Expanded(
                    child: blocked
                        ? ProfileQuickAction(
                            key: const Key('profileUnblock'),
                            icon: Icons.lock_open_outlined,
                            label: 'Unblock',
                            onPressed: _busy ? null : () => _block(true),
                          )
                        : ProfileQuickAction(
                            key: const Key('profileMessage'),
                            icon: roundBubble,
                            label: 'Message',
                            onPressed: _busy || !named
                                ? null
                                : () => _message(chatId),
                          ),
                  ),
                  if (chatId != null && !blocked) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ProfileQuickAction(
                        key: const Key('detailsMute'),
                        icon: muted
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_none,
                        label: muted ? 'Unmute' : 'Mute',
                        onPressed: _busy ? null : () => _mute(chatId, !muted),
                      ),
                    ),
                  ],
                  if (w.inChat?.onSearch case final search?) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ProfileQuickAction(
                        key: const Key('profileSearch'),
                        icon: Icons.search,
                        label: 'Search',
                        // Back to the chat, with its search open.
                        onPressed: () {
                          Navigator.of(context).pop();
                          search();
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(
                semanticsLabel: 'Completing contact action',
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: UiActionError(message: _error!),
            ),
          if (member != null && canManage)
            UiSettingsSection(
              title: 'In this group',
              children: [
                ListTile(
                  key: Key(isAdmin ? 'removeAdmin' : 'makeAdmin'),
                  enabled: !_busy,
                  leading: Icon(
                    isAdmin
                        ? Icons.remove_moderator_outlined
                        : Icons.add_moderator_outlined,
                  ),
                  title: Text(
                    isAdmin ? 'Remove as administrator' : 'Make administrator',
                  ),
                  subtitle: isAdmin
                      ? null
                      : const Text(
                          'Administrators rename the group, remove people '
                          'and choose other administrators.',
                        ),
                  onTap: () => _run(() => member.onRole(!isAdmin)),
                ),
                ProfileSafetyAction(
                  buttonKey: const Key('profileRemoveFromGroup'),
                  icon: Icons.person_remove_outlined,
                  label: 'Remove from group',
                  danger: true,
                  onPressed: _busy ? null : () => _remove(member),
                ),
              ],
            ),
          UiSettingsSection(
            title: 'Privacy and safety',
            children: [
              ListTile(
                key: const Key('detailsVerify'),
                leading: Icon(
                  verified ? Icons.verified_user : Icons.shield_outlined,
                ),
                title: const Text('Security code'),
                subtitle: Text(verified ? 'Verified' : 'Not verified yet'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => VerifyScreen(
                            peerUid: w.peerUid,
                            peerName: w.name,
                          ),
                        ),
                      ),
              ),
              ProfileSafetyAction(
                buttonKey: const Key('detailsBlock'),
                icon: Icons.block,
                label: blocked ? 'Unblock User' : 'Block User',
                danger: !blocked,
                onPressed: _busy ? null : () => _block(blocked),
              ),
              if (chatId != null)
                ProfileSafetyAction(
                  buttonKey: const Key('detailsReport'),
                  icon: roundBubble,
                  iconMark: Icons.priority_high_rounded,
                  label: 'Report Spam',
                  danger: true,
                  onPressed: _busy ? null : () => _report(blocked),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A large round-cornered button under the name: an icon over a short label.
class ProfileQuickAction extends StatelessWidget {
  const ProfileQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      child: Material(
        color: t.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: t.separator),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: enabled ? t.accentText : t.secondaryText,
                  size: 24,
                ),
                const SizedBox(height: 6),
                // One line, shrunk rather than broken with very large text.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: enabled ? t.text : t.secondaryText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One safety row: Block and Report in the danger colour, others in the
/// normal text colour.
class ProfileSafetyAction extends StatelessWidget {
  const ProfileSafetyAction({
    super.key,
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.iconMark,
  });
  final Key buttonKey;
  final IconData icon;

  /// A mark drawn inside a round bubble, in place of [icon].
  final IconData? iconMark;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final color = danger ? t.danger : t.text;
    return InkWell(
      key: buttonKey,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (iconMark case final mark?)
              RoundBubbleIcon(mark: mark, color: color, size: 22)
            else
              Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  height: 1.2,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

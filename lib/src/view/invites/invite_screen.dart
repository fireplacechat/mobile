import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/invite_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/invites/invite_rows.dart';
import 'package:fireplace/src/model/invites/invite_service.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/invites/invite_ticket.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

/// Settings -> Account -> Invite friends: this account's invite codes.
/// It never shows who used a code.
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key});

  /// Opened from the + at the top left of the chat list, so it slides in from
  /// the left and its back arrow sits on the right.
  static Route<void> route() => PageRouteBuilder<void>(
    pageBuilder: (_, _, _) => const InviteScreen(),
    transitionsBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(-1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  Timer? _tick;
  int? _busyRow;
  String? _error;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Ticks once a second only while something on the page counts down.
  void _syncTimer(bool needed) {
    if (needed && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!needed && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  Future<void> _act(
    int row,
    Future<void> Function(InviteService, String) f,
  ) async {
    if (_busyRow != null) return;
    final uid = ref.read(appSessionProvider).value?.uid;
    if (uid == null) return;
    setState(() {
      _busyRow = row;
      _error = null;
    });
    try {
      await f(ref.read(inviteServiceProvider), uid);
    } on InviteException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'That did not finish. Try again.');
    } finally {
      if (mounted) setState(() => _busyRow = null);
    }
  }

  Future<void> _replace(CodeInvite row) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => UiDialog(
        title: const Text('Replace this code?'),
        content: const Text(
          'The old code stops working at once. After this, you can replace '
          'this code once an hour.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmReplaceInvite'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await _act(row.index, (s, uid) => s.replace(uid, row.index, row.slot));
  }

  Future<void> _copy(InviteSlot slot) async {
    try {
      await Clipboard.setData(ClipboardData(text: formatInviteCode(slot.code)));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Invite code copied')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not copy the code. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inviteStateProvider);
    final now = ref.watch(inviteClockProvider)();
    final invites = state.value;
    final rows = invites?.rowsAt(now) ?? const <InviteRow>[];
    _syncTimer(
      rows.any(
        (r) =>
            r is LockedInvite ||
            (r is CodeInvite && r.replaceAfter != null && !r.canReplaceAt(now)),
      ),
    );
    final t = FireplaceUiTokens.of(context);
    return Scaffold(
      appBar: UiAppBar(
        context: context,
        leading: const SizedBox.shrink(),
        leadingWidth: 0,
        title: const Text('Invite friends'),
        actions: [
          IconButton(
            key: const Key('inviteBack'),
            tooltip: 'Back to chats',
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: invites == null
          ? state.hasError
                ? UiEmptyState(
                    title: 'Could not load your invites',
                    message: 'Check your connection and try again.',
                    icon: Icons.mail_outline_rounded,
                    action: TextButton(
                      onPressed: () => ref.invalidate(inviteStateProvider),
                      child: const Text('Try again'),
                    ),
                  )
                : state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : const UiEmptyState(
                    title: 'Sign in to invite friends',
                    message: 'Go back to sign in to your account.',
                  )
          : UiPageScroll(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                  child: Text(
                    'Each code lets one person join Fireplace. Share it '
                    'privately: whoever uses it first gets the account.',
                    style: TextStyle(color: t.secondaryText),
                  ),
                ),
                if (invites.paused)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: UiNotice(
                      key: Key('invitesPaused'),
                      text:
                          'New invites are paused for now. Codes you '
                          'already made still work.',
                    ),
                  ),
                if (_error != null)
                  UiActionError(
                    key: const Key('inviteError'),
                    message: _error!,
                  ),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'You have no invites right now.',
                      key: const Key('noInvites'),
                      style: TextStyle(color: t.secondaryText),
                    ),
                  ),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InviteTicket(
                      row: row,
                      now: now,
                      busy: _busyRow != null,
                      onCreate: () =>
                          _act(row.index, (s, uid) => s.create(uid, row.index)),
                      onCopy: () {
                        if (row is CodeInvite) _copy(row.slot);
                      },
                      onReplace: () {
                        if (row is CodeInvite) _replace(row);
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    'Fireplace does not show you who used your codes.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: t.secondaryText),
                  ),
                ),
              ],
            ),
    );
  }
}

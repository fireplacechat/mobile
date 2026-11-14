import 'package:flutter/material.dart';
import 'package:fireplace/src/model/invites/invite_rows.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

/// `6d 23:14:08`, or `23:14:08` under a day.
String inviteCountdown(Duration d) {
  final s = d.isNegative ? Duration.zero : d;
  String two(int n) => n.toString().padLeft(2, '0');
  final clock =
      '${two(s.inHours % 24)}:${two(s.inMinutes % 60)}:${two(s.inSeconds % 60)}';
  return s.inDays > 0 ? '${s.inDays}d $clock' : clock;
}

/// The same countdown in words, for screen readers.
String inviteCountdownLabel(Duration d) {
  final s = d.isNegative ? Duration.zero : d;
  String unit(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
  return [
    if (s.inDays > 0) unit(s.inDays, 'day'),
    if (s.inHours % 24 > 0) unit(s.inHours % 24, 'hour'),
    if (s.inDays == 0) unit(s.inMinutes % 60, 'minute'),
  ].join(', ');
}

/// One invite row, drawn as a ticket: a code to copy, a button to make one,
/// or a countdown until the row unlocks.
class InviteTicket extends StatelessWidget {
  const InviteTicket({
    super.key,
    required this.row,
    required this.now,
    required this.busy,
    required this.onCreate,
    required this.onCopy,
    required this.onReplace,
  });

  final InviteRow row;
  final DateTime now;
  final bool busy;
  final VoidCallback onCreate;
  final VoidCallback onCopy;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final theme = Theme.of(context);
    final i = row.index;
    final label = Text(
      'INVITE ${i + 1}',
      style: theme.textTheme.labelMedium?.copyWith(
        color: t.secondaryText,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );
    final body = switch (row) {
      LockedInvite(:final readyAt) => _Header(
        label: label,
        trailing: Semantics(
          label: 'Ready in ${inviteCountdownLabel(readyAt.difference(now))}',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 18, color: t.secondaryText),
              const SizedBox(width: 6),
              Text(
                inviteCountdown(readyAt.difference(now)),
                key: Key('inviteCountdown$i'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: t.secondaryText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
      ReadyInvite(:final paused) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(label: label),
          const SizedBox(height: 12),
          FilledButton(
            key: Key('createInvite$i'),
            onPressed: busy || paused ? null : onCreate,
            child: Text(busy ? 'Creating…' : 'Create a code'),
          ),
        ],
      ),
      CodeInvite(:final slot) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            label: label,
            trailing: _Chip(
              text: slot.pending
                  ? 'Saving…'
                  : slot.used
                  ? 'Used'
                  : 'Unused',
              muted: slot.used || slot.pending,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            formatInviteCode(slot.code),
            key: Key('inviteCode$i'),
            style: theme.textTheme.headlineSmall?.copyWith(
              // Not monospace: its O looks like a zero, and codes have no 0.
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              color: slot.used ? t.secondaryText : t.text,
              decoration: slot.used ? TextDecoration.lineThrough : null,
            ),
          ),
          if (!slot.used) ...[
            const SizedBox(height: 14),
            _CodeActions(
              index: i,
              row: row as CodeInvite,
              now: now,
              busy: busy || slot.pending,
              onCopy: onCopy,
              onReplace: onReplace,
            ),
          ],
        ],
      ),
    };
    return Semantics(
      container: true,
      child: Container(
        key: Key('inviteTicket$i'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.panel,
          // The same slight rounding as the theme boxes in Settings.
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colorScheme.outline, width: 1.25),
        ),
        child: body,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label, this.trailing});
  final Widget label;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: label),
      ?trailing,
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.muted});
  final String text;
  final bool muted;
  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: muted ? t.separator.withValues(alpha: .5) : t.selectedRow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: muted ? t.secondaryText : t.accentText),
      ),
    );
  }
}

class _CodeActions extends StatelessWidget {
  const _CodeActions({
    required this.index,
    required this.row,
    required this.now,
    required this.busy,
    required this.onCopy,
    required this.onReplace,
  });
  final int index;
  final CodeInvite row;
  final DateTime now;
  final bool busy;
  final VoidCallback onCopy;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final after = row.replaceAfter;
    final canReplace = row.canReplaceAt(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: Key('copyInvite$index'),
                onPressed: row.slot.pending ? null : onCopy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy code'),
              ),
            ),
            if (after != null) ...[
              const SizedBox(width: 8),
              TextButton(
                key: Key('replaceInvite$index'),
                onPressed: busy || !canReplace ? null : onReplace,
                child: const Text('Replace'),
              ),
            ],
          ],
        ),
        if (after != null && !canReplace)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'You can replace it again in '
              '${inviteCountdown(after.difference(now))}.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: FireplaceUiTokens.of(context).secondaryText,
              ),
            ),
          ),
      ],
    );
  }
}

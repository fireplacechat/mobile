import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/account/takeover.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/account/takeover_alert.dart' show dayLabel;
import 'package:fireplace/src/widgets/status.dart';

/// On the new phone: starting fresh has been asked for and is waiting, or the
/// wait is over and it can be finished (decision 0063).
class StartFreshWaiting extends ConsumerStatefulWidget {
  const StartFreshWaiting({
    super.key,
    required this.uid,
    required this.pending,
  });
  final String uid;
  final PendingStart pending;
  @override
  ConsumerState<StartFreshWaiting> createState() => _StartFreshWaitingState();
}

class _StartFreshWaitingState extends ConsumerState<StartFreshWaiting> {
  Timer? _tick;
  bool _busy = false;
  String? _error;

  DateTime get _now => ref.read(takeoverClockProvider)();

  @override
  void initState() {
    super.initState();
    // The screen changes by itself when the wait ends.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() => _run(() async {
    await ref.read(recoveryServiceProvider).resetIdentity(widget.uid);
    try {
      await ref.read(takeoverServiceProvider).withdraw(widget.uid);
    } catch (_) {
      // The server clears it as well.
    }
    if (mounted) ref.invalidate(appSessionProvider);
  }, 'Could not start fresh. Try again.');

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final theme = Theme.of(context);
    final ready = widget.pending.readyBy(_now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Icon(
            ready
                ? Icons.check_circle_outline_rounded
                : Icons.hourglass_empty_rounded,
            size: 56,
            color: t.accent,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          ready
              ? 'Ready'
              : 'Ready on ${dayLabel(widget.pending.readyAt, _now)}',
          key: const Key('startFreshWhen'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        Text(
          ready
              ? 'Your contacts will see a new security code.'
              : 'Your other devices can stop this.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 32),
        if (_error != null) UiActionError(message: _error!),
        if (ready) ...[
          FilledButton(
            key: const Key('finishStartFresh'),
            onPressed: _busy ? null : _finish,
            child: Text(_busy ? 'Starting…' : 'Start fresh'),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton.tonal(
          key: const Key('withdrawStartFresh'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => ref.read(takeoverServiceProvider).withdraw(widget.uid),
                  'Could not cancel. Try again.',
                ),
          child: const Text('Cancel'),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => ref.read(authServiceProvider).signOut(),
                  'Could not sign out. Try again.',
                ),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

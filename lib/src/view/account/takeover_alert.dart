import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/account/takeover.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Thursday" within the coming week, "19 November" beyond it.
String dayLabel(DateTime when, DateTime now) {
  final local = when.toLocal();
  return local.difference(now.toLocal()).inDays < 6
      ? _weekdays[local.weekday - 1]
      : '${local.day} ${_months[local.month - 1]}';
}

/// Shows, over whatever the person was doing, that a new phone is waiting to
/// take over the account (decision 0063). Once per waiting start, until the
/// app is opened again.
class TakeoverGuard extends ConsumerStatefulWidget {
  const TakeoverGuard({super.key, required this.uid, required this.child});
  final String uid;
  final Widget child;
  @override
  ConsumerState<TakeoverGuard> createState() => _TakeoverGuardState();
}

class _TakeoverGuardState extends ConsumerState<TakeoverGuard> {
  DateTime? _shown;

  void _show(PendingStart? pending) {
    if (pending == null || pending.startedAt == _shown || !mounted) return;
    _shown = pending.startedAt;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => TakeoverAlertScreen(uid: widget.uid),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pendingStartProvider(widget.uid), (_, next) {
      _show(next.value);
    });
    _show(ref.read(pendingStartProvider(widget.uid)).value);
    return widget.child;
  }
}

/// On a device of the account: a new phone is waiting to take over.
class TakeoverAlertScreen extends ConsumerWidget {
  const TakeoverAlertScreen({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = FireplaceUiTokens.of(context);
    final pending = ref.watch(pendingStartProvider(uid)).value;
    final theme = Theme.of(context);
    return PopScope(
      // Leaving is a choice the person makes with a button.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: UiPageScroll(
            maxWidth: 520,
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 28),
            children: [
              Center(
                child: Icon(
                  pending == null
                      ? Icons.check_circle_outline_rounded
                      : Icons.warning_amber_rounded,
                  size: 56,
                  color: pending == null ? t.accent : t.danger,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                pending == null
                    ? 'Stopped'
                    : 'A new phone is taking over your account',
                key: const Key('takeoverTitle'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Text(
                pending == null
                    ? 'Your account stays on this phone.'
                    : 'It takes over on '
                          '${dayLabel(pending.readyAt, ref.watch(takeoverClockProvider)())}.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              if (pending != null) ...[
                FilledButton(
                  key: const Key('stopTakeover'),
                  style: FilledButton.styleFrom(
                    backgroundColor: t.danger,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => StopTakeoverScreen(uid: uid),
                    ),
                  ),
                  child: const Text('Stop them'),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  key: const Key('takeoverIsMe'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('It’s me'),
                ),
              ] else
                FilledButton(
                  key: const Key('takeoverDone'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stopping asks for the password, which a stolen phone does not have, and
/// replaces it, because whoever started this knows it.
class StopTakeoverScreen extends ConsumerStatefulWidget {
  const StopTakeoverScreen({super.key, required this.uid});
  final String uid;
  @override
  ConsumerState<StopTakeoverScreen> createState() => _StopTakeoverScreenState();
}

class _StopTakeoverScreenState extends ConsumerState<StopTakeoverScreen> {
  final _password = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _stop() async {
    if (_busy) return;
    final session = ref.read(appSessionProvider).value;
    if (session == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(takeoverServiceProvider)
          .stop(
            widget.uid,
            session.device,
            password: _password.text,
            newPassword: _next.text,
          );
      // Back to the alert, which now says it is stopped.
      if (mounted) Navigator.of(context).pop();
    } on TakeoverException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not stop it. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: UiAppBar(context: context, title: const Text('Stop them')),
    body: UiPageScroll(
      maxWidth: 520,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      children: [
        const Text('They know your password. Choose a new one.'),
        const SizedBox(height: 20),
        TextField(
          key: const Key('stopPassword'),
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Your password',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('stopNewPassword'),
          controller: _next,
          enabled: !_busy,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _stop(),
          decoration: const InputDecoration(
            labelText: 'New password',
            prefixIcon: Icon(Icons.lock_reset_outlined),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: UiActionError(message: _error!),
          ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('stopConfirm'),
          onPressed: _busy ? null : _stop,
          child: Text(_busy ? 'Stopping…' : 'Stop them'),
        ),
      ],
    ),
  );
}

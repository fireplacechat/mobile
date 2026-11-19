import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/passphrase_lock_providers.dart';
import 'package:fireplace/src/model/lock/passphrase_lock.dart';

/// Locks the app when it comes back after being away longer than the
/// person's choice, or at once when leaving if they chose that (decision
/// 0033). Does nothing while the lock is off.
class AutoLockGuard extends ConsumerStatefulWidget {
  const AutoLockGuard({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<AutoLockGuard> createState() => _AutoLockGuardState();
}

class _AutoLockGuardState extends ConsumerState<AutoLockGuard> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _awaySince;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _left, onShow: _returned);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  PassphraseLockState? get _state => ref.read(passphraseLockProvider).value;

  void _left() {
    final state = _state;
    if (state == null || !state.on || !state.open) return;
    if (state.autoLock == AutoLock.immediately) {
      unawaited(ref.read(passphraseLockProvider.notifier).lockNow());
      return;
    }
    _awaySince = ref.read(autoLockClockProvider)();
  }

  void _returned() {
    final since = _awaySince;
    _awaySince = null;
    final state = _state;
    if (since == null || state == null || !state.on || !state.open) return;
    final away = ref.read(autoLockClockProvider)().difference(since);
    if (away >= state.autoLock.after) {
      unawaited(ref.read(passphraseLockProvider.notifier).lockNow());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Kept loaded, so it is known the moment the app is left.
    ref.watch(passphraseLockProvider);
    return widget.child;
  }
}

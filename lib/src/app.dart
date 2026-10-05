import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/view/account/account_deletion_screens.dart';
import 'package:fireplace/src/view/auth/auth_screen.dart';
import 'package:fireplace/src/ui/new_device_screen.dart';
import 'package:fireplace/src/ui/recovery_screens.dart';
import 'package:fireplace/src/ui/chat_list_screen.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/ui/chat_activity.dart';
import 'package:fireplace/src/view/notifications/in_app_notice.dart';

class FireplaceApp extends StatefulWidget {
  const FireplaceApp({super.key});
  @override
  State<FireplaceApp> createState() => _FireplaceAppState();
}

class _FireplaceAppState extends State<FireplaceApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'fireplace.',
    navigatorKey: _navigatorKey,
    navigatorObservers: [chatRouteObserver],
    builder: (context, child) =>
        InAppNoticeHost(navigatorKey: _navigatorKey, child: child!),
    debugShowCheckedModeBanner: false,
    theme: fireplaceTheme(Brightness.light),
    darkTheme: fireplaceTheme(Brightness.dark),
    home: AuthGate(),
  );
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    return user.when(
      loading: () => _Splash(),
      error: (e, _) => const _AuthError(),
      data: (u) {
        if (u == null) return AuthScreen();
        return ref
            .watch(appSessionProvider)
            .when(
              loading: () => _Splash(message: 'Preparing your account…'),
              error: (e, _) => e is AccountDeletionPending
                  ? DeleteAccountScreen(resume: true)
                  : e is NeedsRecoveryException
                  ? NewDeviceScreen(uid: u.uid)
                  : _SessionError(error: e),
              data: (s) =>
                  s == null ? _Splash() : _BackupNudge(child: ChatListScreen()),
            );
      },
    );
  }
}

/// Auth errors are actionable and never display SDK/internal exception strings.
class _AuthError extends ConsumerWidget {
  const _AuthError();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _StartupFailure(
    title: 'Sign-in unavailable',
    message: 'We could not check your sign-in. Try again, or sign out and sign in again.',
    retryKey: const Key('authRetry'),
    signOutKey: const Key('authSignOut'),
    onRetry: () => ref.invalidate(authUserProvider),
    onSignOut: () async {
      try {
        await ref.read(authServiceProvider).signOut();
      } finally {
        ref.invalidate(authUserProvider);
      }
    },
  );
}

class _Splash extends StatelessWidget {
  const _Splash({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => FireplaceSplash(message: message);
}

class _SessionError extends ConsumerWidget {
  const _SessionError({required this.error});
  final Object error;
  @override
  Widget build(BuildContext context, WidgetRef ref) => _StartupFailure(
    title: error is DeviceRevokedException
        ? 'Device removed'
        : 'Account unavailable',
    message: error is DeviceRevokedException
        ? 'This device was removed from your account. Sign out, then link it again from a device you trust.'
        : 'We could not prepare your account. Try again, or sign out and sign in again.',
    retryKey: const Key('retrySession'),
    signOutKey: const Key('sessionSignOut'),
    onRetry: () => ref.invalidate(appSessionProvider),
    onSignOut: () => ref.read(authServiceProvider).signOut(),
  );
}

class _StartupFailure extends StatefulWidget {
  const _StartupFailure({
    required this.title,
    required this.message,
    required this.retryKey,
    required this.signOutKey,
    required this.onRetry,
    required this.onSignOut,
  });
  final String title, message;
  final Key retryKey, signOutKey;
  final FutureOr<void> Function() onRetry, onSignOut;
  @override
  State<_StartupFailure> createState() => _StartupFailureState();
}

class _StartupFailureState extends State<_StartupFailure> {
  bool _busy = false;
  String? _error;
  Future<void> _run(FutureOr<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'That did not finish. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FireplaceSplash(
    title: widget.title,
    message: [widget.message, ?_error].join('\n\n'),
    actions: [
      FilledButton(
        key: widget.retryKey,
        onPressed: _busy ? null : () => _run(widget.onRetry),
        child: Text(_busy ? 'Please wait…' : 'Try again'),
      ),
      TextButton(
        key: widget.signOutKey,
        onPressed: _busy ? null : () => _run(widget.onSignOut),
        child: const Text('Sign out'),
      ),
    ],
  );
}

/// Reminds the user (once per session) to create a recovery key.
class _BackupNudge extends ConsumerStatefulWidget {
  const _BackupNudge({required this.child});
  final Widget child;
  @override
  ConsumerState<_BackupNudge> createState() => _BackupNudgeState();
}

class _BackupNudgeState extends ConsumerState<_BackupNudge> {
  bool _shown = false;
  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    _messenger?.clearMaterialBanners();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final has = ref.watch(hasBackupProvider).value;
    if (has == false && !_shown) {
      _shown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final m = ScaffoldMessenger.of(context);
        m.showMaterialBanner(
          MaterialBanner(
            key: Key('backupBanner'),
            backgroundColor: FireplaceUiTokens.of(context).warningSurface,
            leading: Icon(
              Icons.key,
              color: FireplaceUiTokens.of(context).danger,
            ),
            content: Text(
              'Create a recovery key so you can restore your account if you '
              'lose this phone.',
            ),
            actions: [
              TextButton(
                onPressed: m.hideCurrentMaterialBanner,
                child: Text('Later'),
              ),
              TextButton(
                onPressed: () {
                  m.hideCurrentMaterialBanner();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => RecoveryKeyScreen()),
                  );
                },
                child: Text('Create'),
              ),
            ],
          ),
        );
      });
    }
    if (has == true) _messenger?.clearMaterialBanners();
    return widget.child;
  }
}

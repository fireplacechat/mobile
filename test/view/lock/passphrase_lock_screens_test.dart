// The passphrase lock's screens (decision 0033): unlocking, a forgotten
// passphrase, setting one, the Settings page, auto-lock and previews.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/src/app.dart';
import 'package:fireplace/src/app/passphrase_lock_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/model/lock/passphrase_lock.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/lock/auto_lock.dart';
import 'package:fireplace/src/view/lock/passphrase_lock_screen.dart';
import 'package:fireplace/src/view/lock/set_passphrase_screen.dart';
import 'package:fireplace/src/view/lock/unlock_screen.dart';
import 'package:fireplace/src/view/settings/push_settings.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/view/settings/privacy_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

const _passphrase = 'correct horse';

class _User extends Fake implements User {
  @override
  String get uid => 'alice';
}

/// The lock without Argon2id or a store: records what the screens ask.
class FakeLock extends PassphraseLockController {
  FakeLock(this.initial);
  final PassphraseLockState initial;
  final calls = <String>[];

  @override
  Future<PassphraseLockState> build() async => initial;

  void _set(PassphraseLockState next) => state = AsyncData(next);

  @override
  Future<bool> unlock(String passphrase) async {
    calls.add('unlock');
    if (passphrase != _passphrase) return false;
    _set(PassphraseLockState(on: true, open: true, autoLock: initial.autoLock));
    return true;
  }

  @override
  Future<bool> verify(String passphrase) async => passphrase == _passphrase;

  @override
  Future<void> enable(String passphrase) async {
    calls.add('enable $passphrase');
    _set(const PassphraseLockState(on: true, open: true));
  }

  @override
  Future<void> disable() async {
    calls.add('disable');
    _set(PassphraseLockState.off);
  }

  @override
  Future<void> lockNow() async {
    calls.add('lock');
    _set(
      PassphraseLockState(on: true, open: false, autoLock: initial.autoLock),
    );
  }

  @override
  Future<void> setAutoLock(AutoLock autoLock) async {
    calls.add('autoLock ${autoLock.name}');
    _set(PassphraseLockState(on: true, open: true, autoLock: autoLock));
  }

  @override
  Future<void> eraseAndSignOut() async => calls.add('erase');
}

void main() {
  late FakeLock lock;
  var now = DateTime.utc(2026, 11, 19, 12);

  Future<UiFixture> open(
    WidgetTester t,
    Widget home, {
    PassphraseLockState state = const PassphraseLockState(on: true, open: true),
    bool push = false,
  }) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    lock = FakeLock(state);
    final f = UiFixture(pushNotifications: push ? fixturePush() : null);
    await f.pushNotifications?.start();
    addTearDown(f.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...f.overrides,
          passphraseLockProvider.overrideWith(() => lock),
          autoLockClockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(theme: fireplaceTheme(Brightness.light), home: home),
      ),
    );
    await settleUi(t);
    return f;
  }

  testWidgets('a wrong passphrase says so; the right one unlocks', (t) async {
    await open(
      t,
      const UnlockScreen(),
      state: const PassphraseLockState(on: true, open: false),
    );
    expect(find.text('Fireplace is locked'), findsOneWidget);
    await t.enterText(find.byKey(const Key('unlockPassphrase')), 'nope nope');
    await t.pump();
    await t.tap(find.byKey(const Key('unlock')));
    await settleUi(t);
    expect(find.text('That is not the passphrase. Try again.'), findsOneWidget);
    // The field is cleared for the next try.
    expect(
      t
          .widget<TextField>(find.byKey(const Key('unlockPassphrase')))
          .controller!
          .text,
      isEmpty,
    );
    await t.enterText(find.byKey(const Key('unlockPassphrase')), _passphrase);
    await t.pump();
    await t.tap(find.byKey(const Key('unlock')));
    await settleUi(t);
    expect(lock.calls, ['unlock', 'unlock']);
    expect(lock.state.value!.locked, isFalse);
  });

  testWidgets('a forgotten passphrase: erase and sign out, after a warning', (
    t,
  ) async {
    await open(
      t,
      const UnlockScreen(),
      state: const PassphraseLockState(on: true, open: false),
    );
    await t.tap(find.byKey(const Key('forgotPassphrase')));
    await t.pumpAndSettle();
    expect(find.text('Erase and set up again?'), findsOneWidget);
    expect(find.textContaining('recovery key'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(lock.calls, isEmpty);
    await t.tap(find.byKey(const Key('forgotPassphrase')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirmEraseLocked')));
    await settleUi(t);
    expect(lock.calls, ['erase']);
  });

  testWidgets('setting a passphrase needs it twice, long enough, and the '
      'warning understood', (t) async {
    await open(t, const SetPassphraseScreen(), state: PassphraseLockState.off);
    Finder button() => find.byKey(const Key('turnOnLock'));
    bool enabled() => t.widget<FilledButton>(button()).onPressed != null;
    await t.enterText(find.byKey(const Key('newPassphrase')), 'short');
    await t.enterText(find.byKey(const Key('repeatPassphrase')), 'short');
    await t.pump();
    expect(enabled(), isFalse);
    await t.tap(find.byKey(const Key('understoodForgotten')));
    await t.pump();
    await t.tap(button());
    await t.pump();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('newPassphrase')), _passphrase);
    await t.enterText(
      find.byKey(const Key('repeatPassphrase')),
      'correct horsf',
    );
    await t.pump();
    await t.tap(button());
    await t.pump();
    expect(find.text('The two passphrases differ.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('repeatPassphrase')), _passphrase);
    await t.pump();
    await t.tap(button());
    await settleUi(t);
    expect(lock.calls, ['enable $_passphrase']);
  });

  testWidgets('the Settings page: lock now, when away, and turning it off '
      'asks for the passphrase', (t) async {
    await open(t, const PassphraseLockScreen());
    expect(find.text('After 5 minutes'), findsOneWidget);
    await t.tap(find.byKey(const Key('autoLock')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('autoLock_oneHour')));
    await t.pumpAndSettle();
    expect(find.text('After 1 hour'), findsOneWidget);

    await t.tap(find.byKey(const Key('turnOffLock')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('confirmPassphrase')), 'wrong one');
    await t.pump();
    await t.tap(find.byKey(const Key('confirmPassphraseAction')));
    await settleUi(t);
    expect(find.text('That is not the passphrase.'), findsOneWidget);
    expect(lock.calls, isNot(contains('disable')));

    await t.tap(find.byKey(const Key('turnOffLock')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('confirmPassphrase')), _passphrase);
    await t.pump();
    await t.tap(find.byKey(const Key('confirmPassphraseAction')));
    await settleUi(t);
    expect(lock.calls, contains('disable'));
    expect(find.byKey(const Key('setUpLock')), findsOneWidget);
  });

  testWidgets('away longer than the choice locks on return; shorter does not', (
    t,
  ) async {
    await open(t, const AutoLockGuard(child: Text('chats')));
    void leave() {
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }

    void come() {
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    leave();
    now = now.add(const Duration(minutes: 4));
    come();
    await t.pump();
    expect(lock.calls, isEmpty);
    leave();
    now = now.add(const Duration(minutes: 5));
    come();
    await t.pump();
    expect(lock.calls, ['lock']);
  });

  testWidgets('"Immediately" locks as soon as the app is left', (t) async {
    await open(
      t,
      const AutoLockGuard(child: Text('chats')),
      state: const PassphraseLockState(
        on: true,
        open: true,
        autoLock: AutoLock.immediately,
      ),
    );
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await t.pump();
    expect(lock.calls, ['lock']);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('Settings shows the lock; previews are off and fixed while it '
      'is on', (t) async {
    final f = await open(t, const PrivacySettingsScreen(), push: true);
    // The fixture's store is a plain one: the row is for the real store.
    expect(find.byKey(const Key('passphraseLock')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...f.overrides,
          passphraseLockProvider.overrideWith(
            () => FakeLock(const PassphraseLockState(on: true, open: true)),
          ),
        ],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: Scaffold(
            body: ListView(
              children: [PushSettingsSection(service: f.pushNotifications!)],
            ),
          ),
        ),
      ),
    );
    await settleUi(t);
    final preview = t.widget<SwitchListTile>(
      find.byKey(const Key('pushPreview')),
    );
    expect(preview.value, isFalse);
    expect(preview.onChanged, isNull);
    expect(find.text('Off while the passphrase lock is on'), findsOneWidget);
  });

  Future<void> launch(WidgetTester t, {required bool locked}) async {
    lock = FakeLock(PassphraseLockState(on: true, open: !locked));
    final f = UiFixture(overrideAuth: false)..hasBackup = true;
    await f.seed();
    addTearDown(f.session.close);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          if (locked) ...f.overridesWithoutSession else ...f.overrides,
          authUserProvider.overrideWith((ref) => Stream.value(_User())),
          passphraseLockProvider.overrideWith(() => lock),
          if (locked)
            appSessionProvider.overrideWith(
              (ref) async => throw const PassphraseLocked(),
            ),
        ],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const AuthGate(),
        ),
      ),
    );
    await settleUi(t);
    await t.pump(const Duration(seconds: 3));
    await settleUi(t);
  }

  testWidgets('a locked account opens on the unlock screen', (t) async {
    await launch(t, locked: true);
    expect(find.byType(UnlockScreen), findsOneWidget);
    expect(find.byType(ChatListScreen), findsNothing);
  });

  testWidgets('locking closes every page above the chat list', (t) async {
    await launch(t, locked: false);
    expect(find.byType(ChatListScreen), findsOneWidget);
    await t.tap(find.byKey(const Key('settings')));
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await lock.lockNow();
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
  });
}

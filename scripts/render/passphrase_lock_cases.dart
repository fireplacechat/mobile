import 'package:fireplace/src/app/passphrase_lock_providers.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/wrapping_secret_store.dart';
import 'package:fireplace/src/model/lock/passphrase_lock.dart';
import 'package:fireplace/src/view/lock/passphrase_lock_screen.dart';
import 'package:fireplace/src/view/lock/set_passphrase_screen.dart';
import 'package:fireplace/src/view/lock/unlock_screen.dart';
import 'package:fireplace/src/view/settings/notification_settings_screen.dart';
import 'package:fireplace/src/view/settings/privacy_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'catalog_case.dart';

/// The passphrase lock (decision 0033) in a fixed state; nothing is derived.
class _Lock extends PassphraseLockController {
  _Lock(this._initial);
  final PassphraseLockState _initial;
  @override
  Future<PassphraseLockState> build() async => _initial;
  @override
  Future<bool> unlock(String passphrase) async => false;
}

List<Override> _lock(PassphraseLockState state) => [
  passphraseLockProvider.overrideWith(() => _Lock(state)),
  // Any store will do: Settings shows the row when the lock can be used.
  passphraseLockServiceProvider.overrideWithValue(
    PassphraseLock(WrappingSecretStore(MemorySecretStore())),
  ),
];

const _locked = PassphraseLockState(on: true, open: false);
const _on = PassphraseLockState(on: true, open: true);

List<CatalogCase> passphraseLockCases() => [
  CatalogCase('lock-unlock', const UnlockScreen(), overrides: _lock(_locked)),
  CatalogCase(
    'lock-unlock-wrong',
    const UnlockScreen(),
    overrides: _lock(_locked),
    act: (t, _) async {
      await t.enterText(find.byKey(const Key('unlockPassphrase')), 'not it');
      await t.pump();
      await t.tap(find.byKey(const Key('unlock')));
      await t.pumpAndSettle();
    },
  ),
  CatalogCase(
    'lock-forgot',
    const UnlockScreen(),
    overrides: _lock(_locked),
    act: (t, _) async {
      await t.tap(find.byKey(const Key('forgotPassphrase')));
      await t.pumpAndSettle();
    },
  ),
  CatalogCase(
    'lock-settings-off',
    const PassphraseLockScreen(),
    overrides: _lock(PassphraseLockState.off),
  ),
  CatalogCase(
    'lock-set-passphrase',
    const SetPassphraseScreen(),
    overrides: _lock(PassphraseLockState.off),
  ),
  CatalogCase(
    'lock-settings-on',
    const PassphraseLockScreen(),
    overrides: _lock(_on),
  ),
  const CatalogCase(
    'lock-when-away',
    AutoLockScreen(selected: AutoLock.fiveMinutes),
  ),
  CatalogCase(
    'lock-settings-row',
    const PrivacySettingsScreen(),
    overrides: _lock(_on),
  ),
  CatalogCase(
    'lock-previews-off',
    const NotificationSettingsScreen(),
    push: true,
    overrides: _lock(_on),
    act: (t, _) async {
      await t.scrollUntilVisible(
        find.byKey(const Key('pushPreview')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
    },
  ),
];

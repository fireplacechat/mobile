// Copy and delete look the same on every page (issue 212): the icons of the
// held-message menu.
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/action_icons.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/devices/devices_screen.dart';
import 'package:fireplace/src/view/recovery/recovery_key_screen.dart';
import 'package:fireplace/src/view/settings/account_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/account_fixture.dart';
import '../support/ui_fixture.dart';

void main() {
  Future<void> open(WidgetTester t, Widget home) async {
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final f = UiFixture();
    addTearDown(f.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...f.overrides,
          recoveryServiceProvider.overrideWithValue(ActionRecovery()),
        ],
        child: MaterialApp(theme: fireplaceTheme(Brightness.light), home: home),
      ),
    );
    await settleUi(t);
  }

  Finder iconIn(String key, IconData icon) =>
      find.descendant(of: find.byKey(Key(key)), matching: find.byIcon(icon));

  testWidgets('Delete account has the bin of the message menu', (t) async {
    await open(t, const AccountSettingsScreen());
    expect(iconIn('deleteAccountTile', ActionIcons.delete), findsOneWidget);
    expect(find.byIcon(Icons.delete_forever), findsNothing);
  });

  testWidgets('removing a device has the same bin', (t) async {
    await open(t, const DevicesScreen());
    expect(
      iconIn('revoke_example-second-device', ActionIcons.delete),
      findsOneWidget,
    );
  });

  testWidgets('copying the recovery key has the copy icon of the menu', (
    t,
  ) async {
    await open(t, const RecoveryKeyScreen());
    await t.tap(find.byKey(const Key('createRecovery')));
    await settleUi(t);
    expect(iconIn('copyRecoveryKey', ActionIcons.copy), findsOneWidget);
  });
}

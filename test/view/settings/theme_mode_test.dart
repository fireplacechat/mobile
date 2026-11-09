import 'dart:async';

import 'package:fireplace/src/app.dart';
import 'package:fireplace/src/app/theme_preference.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/view/auth/auth_screen.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

class UnwritableStore extends MemorySecretStore {
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('storage unavailable');
}

Future<void> openSettings(
  WidgetTester tester, {
  MemorySecretStore? store,
}) async {
  final fixture = UiFixture(secrets: store);
  await fixture.seed();
  addTearDown(fixture.session.close);
  await tester.pumpWidget(
    ProviderScope(overrides: fixture.overrides, child: const FireplaceApp()),
  );
  await tester.pumpAndSettle();
  unawaited(
    Navigator.of(tester.element(find.byType(AuthScreen)))
        .push<void>(MaterialPageRoute(builder: (_) => const SettingsScreen())),
  );
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String mode) async {
  await tester.ensureVisible(find.byKey(const Key('themeMode')));
  await tester.tap(find.byKey(const Key('themeMode')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(Key('theme-$mode')));
  await tester.tap(find.byKey(Key('theme-$mode')));
  await tester.pumpAndSettle();
}

Brightness brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(SettingsScreen))).brightness;

void main() {
  testWidgets('system follows the device and manual choices override it', (
    tester,
  ) async {
    final platform = tester.platformDispatcher;
    addTearDown(platform.clearPlatformBrightnessTestValue);
    platform.platformBrightnessTestValue = Brightness.dark;
    await openSettings(tester);
    expect(brightness(tester), Brightness.dark);
    platform.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(brightness(tester), Brightness.light);

    await choose(tester, 'dark');
    expect(brightness(tester), Brightness.dark);
    platform.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    await choose(tester, 'light');
    expect(brightness(tester), Brightness.light);

    await choose(tester, 'system');
    expect(brightness(tester), Brightness.dark);
    platform.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(brightness(tester), Brightness.light);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets(
    'a failed save shows a plain error and leaves the theme unchanged',
    (tester) async {
      final store = UnwritableStore();
      store.data[ThemePreference.storageKey] = 'light';
      await openSettings(tester, store: store);
      await choose(tester, 'dark');
      expect(brightness(tester), Brightness.light);
      expect(
        find.text('Could not save your theme. Try again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('theme choices fit a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openSettings(tester);
    await choose(tester, 'dark');
    expect(brightness(tester), Brightness.dark);
    expect(tester.takeException(), isNull);
  });
}

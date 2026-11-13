import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:fireplace/src/app.dart';
import 'package:fireplace/src/app/theme_preference.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/view/auth/auth_screen.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

class ThemeTestStore extends MemorySecretStore {
  bool failWrite = false;
  Completer<void>? hold;
  int writes = 0;
  @override
  Future<void> write(String key, String value) async {
    if (key == ThemePreference.storageKey) {
      writes++;
      await hold?.future;
      if (failWrite) throw StateError('storage unavailable');
    }
    await super.write(key, value);
  }
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

Future<void> openPicker(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('themeMode')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('themeMode')));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String mode) async {
  // A preview taller than the viewport cannot itself be made fully visible.
  // Its label remains reachable by scrolling, and is part of the same target.
  final label = find.text(mode == 'dark' ? 'Dark' : 'Light');
  await tester.ensureVisible(label);
  await tester.pumpAndSettle();
  await tester.tap(label);
  await tester.pumpAndSettle();
}

Brightness brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.text('Choose your theme'))).brightness;

void expectSelected(WidgetTester tester, String mode) {
  for (final option in ['light', 'dark']) {
    final semantics = tester.getSemantics(find.byKey(Key('theme-$option')));
    expect(
      semantics.getSemanticsData().flagsCollection.isSelected,
      option == mode ? Tristate.isTrue : Tristate.isFalse,
    );
  }
}

void themeTestWidgets(String name, WidgetTesterCallback test) {
  testWidgets(name, (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await test(tester);
    } finally {
      semantics.dispose();
    }
  });
}

void main() {
  themeTestWidgets(
    'the full page saves each preview and keeps explicit choices',
    (tester) async {
      final platform = tester.platformDispatcher;
      addTearDown(platform.clearPlatformBrightnessTestValue);
      platform.platformBrightnessTestValue = Brightness.dark;
      final store = ThemeTestStore();
      await openSettings(tester, store: store);
      await openPicker(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Choose your theme'), findsOneWidget);
      expect(find.text('System'), findsNothing);
      expect(brightness(tester), Brightness.dark);
      expectSelected(tester, 'dark');
      platform.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.light);
      expectSelected(tester, 'light');
      expect(store.writes, 0);

      await choose(tester, 'dark');
      expect(brightness(tester), Brightness.dark);
      expectSelected(tester, 'dark');
      expect(store.data[ThemePreference.storageKey], 'dark');
      platform.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.dark);
      await choose(tester, 'light');
      expect(brightness(tester), Brightness.light);
      expectSelected(tester, 'light');
      expect(store.data[ThemePreference.storageKey], 'light');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await openPicker(tester);
      expectSelected(tester, 'light');
    },
  );

  for (final device in Brightness.values) {
    themeTestWidgets(
      'tapping the matching System preview saves ${device.name}',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = device;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final store = ThemeTestStore();
        await openSettings(tester, store: store);
        await openPicker(tester);
        expect(store.writes, 0);
        await choose(tester, device.name);
        expect(store.data[ThemePreference.storageKey], device.name);
        tester.platformDispatcher.platformBrightnessTestValue =
            device == Brightness.dark ? Brightness.light : Brightness.dark;
        await tester.pumpAndSettle();
        expect(brightness(tester), device);
      },
    );
  }

  themeTestWidgets(
    'a failed save shows a plain error and leaves the theme unchanged',
    (tester) async {
      final store = ThemeTestStore()..failWrite = true;
      store.data[ThemePreference.storageKey] = 'light';
      await openSettings(tester, store: store);
      await openPicker(tester);
      await choose(tester, 'dark');
      expect(brightness(tester), Brightness.light);
      expectSelected(tester, 'light');
      expect(
        find.text('Could not save your theme. Try again.'),
        findsOneWidget,
      );
      store.failWrite = false;
      await choose(tester, 'dark');
      expect(brightness(tester), Brightness.dark);
      expectSelected(tester, 'dark');
      expect(store.data[ThemePreference.storageKey], 'dark');
    },
  );

  themeTestWidgets(
    'a pending save disables choices and safely finishes after back',
    (tester) async {
      final store = ThemeTestStore()..hold = Completer<void>();
      store.data[ThemePreference.storageKey] = 'light';
      await openSettings(tester, store: store);
      await openPicker(tester);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(store.writes, 1);
      for (final option in ['light', 'dark']) {
        expect(
          tester
              .widget<Semantics>(find.byKey(Key('theme-$option')))
              .properties
              .enabled,
          isFalse,
        );
      }
      await tester.tap(find.text('Light'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      store.hold!.complete();
      await tester.pumpAndSettle();
      expect(store.writes, 1);
      expect(store.data[ThemePreference.storageKey], 'dark');
      expect(tester.takeException(), isNull);
    },
  );

  for (final (size, scale) in [
    (const Size(320, 568), 1.35),
    (const Size(320, 640), 2.0),
    (const Size(375, 812), 1.35),
    (const Size(430, 932), 1.35),
    (const Size(812, 375), 1.35),
    (const Size(768, 1024), 1.35),
    (const Size(1024, 768), 1.35),
  ]) {
    themeTestWidgets('theme previews fit $size with text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openSettings(tester);
      await openPicker(tester);
      final light = tester.getRect(
        find.byKey(const Key('theme-preview-light')),
      );
      final dark = tester.getRect(find.byKey(const Key('theme-preview-dark')));
      expect(light.top, closeTo(dark.top, .1));
      expect(light.width, closeTo(dark.width, .1));
      expect(light.right, lessThan(dark.left));
      expect(light.shortestSide, greaterThanOrEqualTo(48));
      final heading = tester.getRect(find.text('Choose your theme'));
      expect(heading.left, closeTo(light.left, .1));
      for (final (label, preview) in [('Light', light), ('Dark', dark)]) {
        final text = tester.getRect(find.text(label));
        expect(text.center.dx, closeTo(preview.center.dx, .1));
        expect(text.top, greaterThan(preview.bottom));
      }
      await choose(tester, 'dark');
      expectSelected(tester, 'dark');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      expect(tester.takeException(), isNull);
    });
  }
}

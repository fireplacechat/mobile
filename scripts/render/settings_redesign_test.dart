// Settings redesign for review (issue 249): the main page and every
// category page in light and dark, on iOS and Android, a narrow phone at 200%
// text, the collapsed title, the licence page, and frames of moving through
// the pages. Not part of the byte-identical catalog.
//   TZ=UTC flutter test scripts/render/settings_redesign_test.dart
//   python scripts/render/frames_to_gif.py build/frames/settings-pages
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/app/passphrase_lock_providers.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/wrapping_secret_store.dart';
import 'package:fireplace/src/model/lock/passphrase_lock.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/settings/push_settings.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart';

const _out = 'build/settings-redesign';

class _Lock extends PassphraseLockController {
  @override
  Future<PassphraseLockState> build() async => PassphraseLockState.off;
}

Future<void> _write(WidgetTester t, GlobalKey boundary, String path) async {
  final renderer =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final png = await t.runAsync(() async {
    final image = await renderer.toImage(pixelRatio: 2);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List();
    } finally {
      image.dispose();
    }
  });
  File('$_out/$path')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!);
}

Future<GlobalKey> _mount(
  WidgetTester t,
  Brightness brightness, {
  TargetPlatform platform = TargetPlatform.iOS,
  Size size = const Size(390, 780),
  double textScale = 1,
}) async {
  // Real blurred shadows; each test puts the setting back at its end.
  debugDisableShadows = false;
  final f = UiFixture(pushNotifications: fixturePush());
  await f.seed();
  addTearDown(f.session.close);
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.view.padding = const FakeViewPadding(top: 47);
  addTearDown(t.view.reset);
  final boundary = GlobalKey();
  final theme = fireplaceTheme(brightness).copyWith(platform: platform);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...f.overrides,
        passphraseLockProvider.overrideWith(_Lock.new),
        passphraseLockServiceProvider.overrideWithValue(
          PassphraseLock(WrappingSecretStore(MemorySecretStore())),
        ),
        appleWordingProvider.overrideWithValue(platform == TargetPlatform.iOS),
        notificationPreviewAvailableProvider.overrideWithValue(true),
      ],
      child: RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(
              fontFamilyFallback: const ['PreviewEmoji'],
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const SettingsScreen(),
        ),
      ),
    ),
  );
  await _settle(t);
  return boundary;
}

Future<void> _settle(WidgetTester t) async {
  await settleUi(t);
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await t.pumpAndSettle();
}

Future<void> _openCategory(WidgetTester t, SettingsCategory category) async {
  final row = find.byKey(category.rowKey);
  await t.ensureVisible(row);
  await t.pumpAndSettle();
  await t.tap(row);
  await _settle(t);
}

void main() {
  setUpAll(loadFonts);

  for (final (platform, os) in [
    (TargetPlatform.iOS, 'ios'),
    (TargetPlatform.android, 'android'),
  ]) {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;
      testWidgets('$os $mode main and categories', (t) async {
        final boundary = await _mount(t, brightness, platform: platform);
        await _write(t, boundary, '$os-$mode-main.png');
        for (final category in SettingsCategory.values) {
          await _openCategory(t, category);
          await _write(t, boundary, '$os-$mode-${category.name}.png');
          await t.pageBack();
          await _settle(t);
        }
        debugDisableShadows = true;
      });
    }
  }

  for (final brightness in Brightness.values) {
    final mode = brightness.name;
    testWidgets('narrow phone at 200% text $mode', (t) async {
      final boundary = await _mount(
        t,
        brightness,
        size: const Size(320, 640),
        textScale: 2,
      );
      await _write(t, boundary, 'narrow-large-$mode-main.png');
      for (final category in SettingsCategory.values) {
        await _openCategory(t, category);
        await _write(t, boundary, 'narrow-large-$mode-${category.name}.png');
        await t.pageBack();
        await _settle(t);
      }
      debugDisableShadows = true;
    });

    testWidgets('collapsed title and licences $mode', (t) async {
      // A shorter phone, so the page has to scroll.
      final boundary = await _mount(t, brightness, size: const Size(390, 620));
      await _openCategory(t, SettingsCategory.notifications);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await _settle(t);
      await _write(t, boundary, 'ios-$mode-notifications-scrolled.png');
      await t.pageBack();
      await _settle(t);
      await _openCategory(t, SettingsCategory.help);
      await t.tap(find.byKey(const Key('openLicences')));
      await _settle(t);
      await _write(t, boundary, 'ios-$mode-licences.png');
      debugDisableShadows = true;
    });
  }

  testWidgets('moving through the pages', (t) async {
    final boundary = await _mount(t, Brightness.light);
    var frame = 0;
    Future<void> capture(int count) async {
      for (var i = 0; i < count; i++) {
        await t.pump(const Duration(milliseconds: 40));
        final name = (frame++).toString().padLeft(3, '0');
        await _write(t, boundary, '../frames/settings-pages/$name.png');
      }
    }

    await capture(4);
    for (final category in [
      SettingsCategory.privacy,
      SettingsCategory.appearance,
      SettingsCategory.help,
    ]) {
      await t.tap(find.byKey(category.rowKey));
      await capture(12);
      await capture(4);
      await t.pageBack();
      await capture(12);
    }
    await t.pumpAndSettle();
    debugDisableShadows = true;
  });
}

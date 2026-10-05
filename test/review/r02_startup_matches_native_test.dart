// REVIEW R02: the in-app startup screen must hand off from the NATIVE launch screen without a visible
// change. The native screens (see android/.../drawable*/launch_background.xml and the iOS storyboard)
// draw the lockup 200 dp wide, centred, on cream. On b01a65d the splash uses a full-screen wallpaper
// (BoxFit.cover): the logo is ~37-43% of the screen width (150-180 dp on phones, 320 dp on tablets) and
// centred at 54% of the height, the dark theme switches to charcoal while the native splash stays cream,
// and a 1440x3120 bitmap is decoded (17 MB) and kept in the image cache.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fireplace/src/ui/lockup.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const nativeLockupWidth =
    200.0; // lockupLogicalWidth: what the native launch screens draw
// Content box of the lockup inside its 648-unit viewBox (from the approved wallpaper): 600/648 wide.
const contentWidthFraction = 600 / 648;
const approvedDarkBackground = Color(
  0xFF333F48,
); // corner pixel of the approved orange-on-charcoal wallpaper
const approvedLightBackground = Color(0xFFFAF7F0);

class Box {
  Box(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;
  double get width => right - left;
  double get cx => (left + right) / 2;
  double get cy => (top + bottom) / 2;
}

Future<Box> measureLockup(WidgetTester t, Size size, Brightness b) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final key = GlobalKey();
  await t.pumpWidget(
    MaterialApp(
      theme: fireplaceTheme(b),
      home: RepaintBoundary(key: key, child: const FireplaceSplash()),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
  final cardTop = find.byType(Card).evaluate().isEmpty
      ? size.height
      : t.getTopLeft(find.byType(Card)).dy;
  final img = await t.runAsync(
    () async =>
        (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage(pixelRatio: 1),
  );
  final data = (await t.runAsync(
    () => img!.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final w = img!.width;
  int px(int x, int y) => data.getUint32((y * w + x) * 4);
  final bg = px(2, 2);
  int minX = w, maxX = 0, minY = img.height, maxY = 0;
  for (var y = 0; y < cardTop - 4 && y < img.height; y++) {
    for (var x = 0; x < w; x++) {
      final p = px(x, y);
      int d(int s) => ((p >> s) & 0xFF) - ((bg >> s) & 0xFF);
      if (d(24).abs() + d(16).abs() + d(8).abs() > 120) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  expect(maxX, greaterThan(minX), reason: 'a lockup should be visible');
  return Box(minX.toDouble(), minY.toDouble(), maxX + 1.0, maxY + 1.0);
}

void main() {
  for (final b in [Brightness.light, Brightness.dark]) {
    for (final size in const [
      Size(360, 640),
      Size(390, 844),
      Size(412, 915),
      Size(768, 1024),
    ]) {
      testWidgets(
        'lockup matches the native launch screen: ${b.name} ${size.width.toInt()}x${size.height.toInt()}',
        (t) async {
          final box = await measureLockup(t, size, b);
          expect(
            box.width,
            closeTo(nativeLockupWidth * contentWidthFraction, 4),
            reason:
                'logo width ${box.width.toStringAsFixed(1)} dp vs native ${(nativeLockupWidth * contentWidthFraction).toStringAsFixed(1)} dp',
          );
          expect(box.cx, closeTo(size.width / 2, 3));
          expect(
            box.cy,
            closeTo(size.height / 2, 3),
            reason:
                'logo centre ${box.cy.toStringAsFixed(1)} vs screen centre ${size.height / 2}',
          );
        },
      );
    }
  }

  testWidgets(
    'splash background colours are the approved ones (no 1-unit typo)',
    (t) async {
      for (final (b, want) in [
        (Brightness.light, approvedLightBackground),
        (Brightness.dark, approvedDarkBackground),
      ]) {
        await t.pumpWidget(
          MaterialApp(
            theme: fireplaceTheme(b),
            themeAnimationDuration: Duration.zero,
            home: const FireplaceSplash(),
          ),
        );
        await t.pump();
        expect(
          t.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          want,
          reason: '${b.name} splash scaffold colour',
        );
      }
    },
  );

  test('Android native launch background follows the dark theme too (no cream flash before a charcoal splash)', () {
    String color(String path) {
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: '$path should exist');
      final m = RegExp(
        r'<color name="splash_background">#([0-9A-Fa-f]{6})</color>',
      ).firstMatch(f.readAsStringSync());
      expect(m, isNotNull, reason: '$path must define splash_background');
      return m!.group(1)!.toUpperCase();
    }

    expect(color('android/app/src/main/res/values/colors.xml'), 'FAF7F0');
    expect(color('android/app/src/main/res/values-night/colors.xml'), '333F48');
  });

  testWidgets(
    'Android <= 11 dark launch bitmaps exist and are readable on charcoal (light wordmark, not dark ink)',
    (t) async {
      for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        final f = File(
          'android/app/src/main/res/drawable-night-$d/splash_lockup.png',
        );
        expect(f.existsSync(), isTrue, reason: '${f.path} should exist');
        final bytes = f.readAsBytesSync();
        final codec = await t.runAsync(
          () => ui.instantiateImageCodec(Uint8List.fromList(bytes)),
        );
        final img = (await t.runAsync(() => codec!.getNextFrame()))!.image;
        final data = (await t.runAsync(
          () => img.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        var light = 0, darkInk = 0;
        for (var i = 0; i < data.lengthInBytes; i += 4) {
          final r = data.getUint8(i),
              g = data.getUint8(i + 1),
              bl = data.getUint8(i + 2),
              a = data.getUint8(i + 3);
          if (a < 200) continue;
          if (r > 225 && g > 225 && bl > 225) light++;
          if (r < 70 && g < 80 && bl < 70) darkInk++;
        }
        expect(
          light,
          greaterThan(500),
          reason: '$d: a light wordmark is needed on charcoal',
        );
        expect(
          darkInk,
          0,
          reason: '$d: dark ink would be invisible on charcoal',
        );
      }
    },
  );

  testWidgets(
    'the startup screen does not keep a multi-megabyte bitmap in the image cache',
    (t) async {
      PaintingBinding.instance.imageCache.clear();
      await t.pumpWidget(
        MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const FireplaceSplash(),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await t.pump();
      }
      await t.pumpWidget(const SizedBox());
      await t.pump();
      final mb = PaintingBinding.instance.imageCache.currentSizeBytes / 1048576;
      expect(
        mb,
        lessThan(2),
        reason:
            'image cache after leaving the splash: ${mb.toStringAsFixed(1)} MB',
      );
    },
  );
}

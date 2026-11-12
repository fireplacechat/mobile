import 'dart:typed_data';

import 'package:fireplace/src/styles/brand/fireflies.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

final _boundary = GlobalKey();

Future<void> _pumpSplash(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  bool still = false,
  List<Widget> actions = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: fireplaceTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: still),
        child: child!,
      ),
      home: RepaintBoundary(
        key: _boundary,
        child: FireplaceSplash(actions: actions),
      ),
    ),
  );
}

Future<Uint8List> _pixels(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final image =
          await (_boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      return (await image.toByteData())!.buffer.asUint8List();
    }))!;

// Both styles share the timing; a second more puts a flash in view.
final _fullyIn =
    FireflyStyle.dark.appearAfter +
    FireflyStyle.dark.fadeIn +
    const Duration(seconds: 1);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'the first frame matches the native launch screen (${brightness.name})',
      (tester) async {
        await _pumpSplash(tester, brightness: brightness, still: true);
        final plain = await _pixels(tester);
        await _pumpSplash(tester, brightness: brightness);
        expect(find.byType(Fireflies), findsOneWidget);
        expect(await _pixels(tester), plain);
      },
    );

    testWidgets('fireflies appear after the fade-in (${brightness.name})', (
      tester,
    ) async {
      await _pumpSplash(tester, brightness: brightness, still: true);
      final plain = await _pixels(tester);
      await _pumpSplash(tester, brightness: brightness);
      await tester.pump(_fullyIn);
      expect(await _pixels(tester), isNot(plain));
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('no glow ever reaches the circle around the logo '
        '(${brightness.name})', (tester) async {
      await _pumpSplash(tester, brightness: brightness, still: true);
      final plain = await _pixels(tester);
      await _pumpSplash(tester, brightness: brightness);
      final style = brightness == Brightness.dark
          ? FireflyStyle.dark
          : FireflyStyle.light;
      final clear = FireflyPainter.clearRadius(
        Size(lockupLogicalWidth, FireplaceLockup.heightFor(lockupLogicalWidth)),
        style,
      );
      expect(clear, greaterThan(lockupLogicalWidth / 2));
      const centre = Offset(390 / 2, 844 / 2);
      var outside = 0;
      // Twenty moments spread over more than one flash and drift cycle.
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 700));
        final now = await _pixels(tester);
        for (var i = 0; i < now.length; i += 4) {
          if (now[i] == plain[i] &&
              now[i + 1] == plain[i + 1] &&
              now[i + 2] == plain[i + 2]) {
            continue;
          }
          final p = Offset((i ~/ 4 % 390).toDouble(), (i ~/ 4 ~/ 390) * 1.0);
          expect(
            (p - centre).distance,
            greaterThanOrEqualTo(clear),
            reason: 'pixel $p changed inside the clear circle',
          );
          outside++;
        }
      }
      expect(outside, greaterThan(0), reason: 'fireflies were drawn');
    });
  }

  testWidgets('the same moment always looks the same', (tester) async {
    await _pumpSplash(tester);
    await tester.pump(_fullyIn);
    final first = await _pixels(tester);
    await tester.pumpWidget(const SizedBox());
    await _pumpSplash(tester);
    await tester.pump(_fullyIn);
    expect(await _pixels(tester), first);
  });

  testWidgets('reduced motion: no fireflies and no animation frames', (
    tester,
  ) async {
    await _pumpSplash(tester, still: true);
    await tester.pump(_fullyIn);
    expect(find.byType(CustomPaint).evaluate().where(_isFireflies), isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a startup error screen has no fireflies', (tester) async {
    await _pumpSplash(
      tester,
      actions: [TextButton(onPressed: () {}, child: const Text('Try again'))],
    );
    expect(find.byType(Fireflies), findsNothing);
  });

  testWidgets('the animation stops when the loading screen goes', (
    tester,
  ) async {
    await _pumpSplash(tester);
    await tester.pump(_fullyIn);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

bool _isFireflies(Element e) =>
    (e.widget as CustomPaint).painter is FireflyPainter;

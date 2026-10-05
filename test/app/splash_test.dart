import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> decode(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  return (await codec.getNextFrame()).image;
}

void main() {
  testWidgets(
    'the in-app lockup matches the art pack render (cream wallpaper)',
    (t) async {
      // reference: the same lockup rendered from the pack's own SVG by scripts/brand/gen_lockup.py
      final ref = File('test/fixtures/lockup_reference.png').readAsBytesSync();
      final key = GlobalKey();
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: fireplaceCream,
                width: 324,
                height: FireplaceLockup.heightFor(324),
                child: const FireplaceLockup(width: 324),
              ),
            ),
          ),
        ),
      );
      final result = await t.runAsync(() async {
        final ro =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final mine = await ro.toImage(pixelRatio: 1);
        final theirs = await decode(ref);
        final a = (await mine.toByteData())!.buffer.asUint8List();
        final b = (await theirs.toByteData())!.buffer.asUint8List();
        return (mine.width, mine.height, theirs.width, theirs.height, a, b);
      });
      final (w, h, rw, rh, a, b) = result!;
      expect((w, h), (rw, rh), reason: 'same pixel size as the reference');
      var total = 0, bad = 0;
      for (var i = 0; i < a.length; i += 4) {
        final d =
            (a[i] - b[i]).abs() +
            (a[i + 1] - b[i + 1]).abs() +
            (a[i + 2] - b[i + 2]).abs();
        total += d;
        if (d > 120) bad++; // clearly different pixel (anti-aliasing edges stay below this)
      }
      final pixels = a.length ~/ 4;
      expect(
        total / pixels / 3,
        lessThan(1.0),
        reason: 'mean per-channel difference',
      );
      expect(
        bad / pixels,
        lessThan(0.002),
        reason: 'share of clearly different pixels',
      );
    },
  );

  testWidgets('the loading screen shows only the approved lockup on cream', (
    t,
  ) async {
    // A phone-sized screen (the default test window is a short 800x600).
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const MaterialApp(home: FireplaceSplash(message: 'Preparing keys…')),
    );
    expect(find.byType(FireplaceLockup), findsOneWidget);
    expect(
      find.byKey(const Key('startupWallpaper')),
      findsNothing,
      reason: 'no multi-megabyte bitmap on the startup screen',
    );
    expect(find.text('Preparing keys…'), findsNothing);
    final scaffold = t.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, fireplaceCream);
    expect(find.text('Opening Fireplace'), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(t.takeException(), isNull);
  });
}

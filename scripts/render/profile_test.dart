// A person's profile (issue 244), for review; not part of the byte-identical
// catalog. With a chat, with no chat yet, blocked, and narrow with large text.
//   TZ=UTC flutter test scripts/render/profile_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/profile/person_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final brightness in Brightness.values) {
    for (final state in ['chat', 'new', 'blocked', 'large']) {
      testWidgets('${brightness.name} $state', (t) async {
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        final large = state == 'large';
        t.view.physicalSize = Size(large ? 320 : 390, 780);
        t.view.devicePixelRatio = 1;
        t.view.padding = const FakeViewPadding(top: 47);
        addTearDown(t.view.reset);
        final f = UiFixture();
        await f.seed();
        addTearDown(f.session.close);
        if (state == 'blocked') f.blocked = {'fred'};
        final peer = state == 'new' ? 'zoe' : 'fred';
        final key = GlobalKey();
        await t.pumpWidget(
          ProviderScope(
            overrides: f.overrides,
            child: RepaintBoundary(
              key: key,
              child: MediaQuery(
                data: MediaQueryData(
                  size: Size(large ? 320 : 390, 780),
                  padding: const EdgeInsets.only(top: 47),
                  textScaler: TextScaler.linear(large ? 2 : 1),
                ),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: fireplaceTheme(brightness),
                  home: PersonProfileScreen(peerUid: peer, name: peer),
                ),
              ),
            ),
          ),
        );
        await settleUi(t);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            File('build/profile/${brightness.name}-$state.png')
              ..createSync(recursive: true)
              ..writeAsBytesSync(data!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        debugDisableShadows = shadows;
      });
    }
  }
}

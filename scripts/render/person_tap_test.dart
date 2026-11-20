// The press highlight on a person's avatar and name (issue 245), for
// review; not part of the byte-identical catalog. The top of a 1:1 chat on
// iOS and Android, in light and dark, while the finger is down.
//   TZ=UTC flutter test scripts/render/person_tap_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final brightness in Brightness.values) {
      for (final part in ['chatAvatar', 'chatDetails']) {
        final name =
            '${platform.name}-${brightness.name}-'
            '${part == 'chatAvatar' ? 'avatar' : 'name'}';
        testWidgets(name, (t) async {
          final shadows = debugDisableShadows;
          debugDisableShadows = false;
          t.view.physicalSize = const Size(390, 200);
          t.view.devicePixelRatio = 1;
          t.view.padding = const FakeViewPadding(top: 47);
          addTearDown(t.view.reset);
          final f = UiFixture();
          await f.seed();
          addTearDown(f.session.close);
          final key = GlobalKey();
          await t.pumpWidget(
            ProviderScope(
              overrides: f.overrides,
              child: RepaintBoundary(
                key: key,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: fireplaceTheme(brightness)
                      .copyWith(platform: platform),
                  home: const ChatScreen(chatId: 'alice_fred'),
                ),
              ),
            ),
          );
          await settleUi(t);
          final finger = await t.startGesture(
            t.getCenter(find.byKey(Key(part))),
          );
          // The press shows after the tap timeout, then fades in.
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 80));
          }
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          await t.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 3);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File('build/person-tap/$name.png')
                ..createSync(recursive: true)
                ..writeAsBytesSync(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
          await finger.cancel();
          await t.pumpAndSettle();
          debugDisableShadows = shadows;
        });
      }
    }
  }
}

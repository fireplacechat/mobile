// Renders the thin scroll bar while a list is moving, into
// build/renders/scrollbar/, for review and for pull requests:
//
//   TZ=UTC flutter test scripts/render/render_scrollbar_test.dart
//
// The bar only shows during a scroll, so each image is taken with a finger
// still down. Settings, and a conversation long enough to scroll.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

void main() {
  final screens = <String, (Widget, Offset)>{
    'settings': (const SettingsScreen(), const Offset(0, -260)),
    // A conversation is a reversed list: dragging down shows older messages.
    'conversation': (
      const ChatScreen(chatId: 'alice_fred'),
      const Offset(0, 260),
    ),
  };
  for (final brightness in Brightness.values) {
    for (final MapEntry(key: name, value: (screen, drag)) in screens.entries) {
      testWidgets('scroll bar, $name, ${brightness.name}', (t) async {
        await t.runAsync(loadFonts);
        final previousShadows = debugDisableShadows;
        debugDisableShadows = false;
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final fixture = UiFixture();
        await fixture.seed();
        addTearDown(fixture.session.close);
        for (var i = 0; i < 30; i++) {
          await fixture.chat.store.add(
            LocalMessage(
              id: 'long-$i',
              chatId: 'alice_fred',
              senderUid: i.isEven ? 'fred' : 'alice',
              senderDevice: 'device',
              outgoing: i.isOdd,
              sentAt: fixtureTime.subtract(Duration(days: 3, minutes: 60 - i)),
              body: i.isEven
                  ? 'Shall we take the early train on Saturday?'
                  : 'Yes. I will bring the tickets.',
            ),
          );
        }
        final boundary = GlobalKey();
        final theme = fireplaceTheme(brightness);
        await t.pumpWidget(
          ProviderScope(
            overrides: fixture.overrides,
            child: RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.copyWith(
                  textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
                ),
                home: screen,
              ),
            ),
          ),
        );
        await settleUi(t);
        final gesture = await t.startGesture(const Offset(195, 420));
        await gesture.moveBy(drag / 4);
        await gesture.moveBy(drag);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        final renderer =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final png = await t.runAsync(() async {
          final image = await renderer.toImage(pixelRatio: 2);
          try {
            return (await image.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List();
          } finally {
            image.dispose();
          }
        });
        File('build/renders/scrollbar/${brightness.name}-$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!);
        await gesture.up();
        await t.pump(const Duration(seconds: 3));
        await t.pumpAndSettle();
        // The test binding checks this is back before the body ends.
        debugDisableShadows = previousShadows;
      });
    }
  }
}

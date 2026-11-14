// Renders the menu a held conversation opens in the chat list, and the
// question before deleting one on this phone, into
// build/renders/chat-list-menu/, for review and for pull requests:
//
//   TZ=UTC flutter test scripts/render/render_chat_list_menu_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

void main() {
  for (final brightness in Brightness.values) {
    for (final state in ['menu', 'delete-question']) {
      testWidgets('chat list $state, ${brightness.name}', (t) async {
        await t.runAsync(loadFonts);
        final previousShadows = debugDisableShadows;
        debugDisableShadows = false;
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final fixture = UiFixture();
        await fixture.seed();
        addTearDown(fixture.session.close);
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
                home: const ChatListScreen(),
              ),
            ),
          ),
        );
        await settleUi(t);
        await t.longPress(
          find.byKey(const ValueKey('conversation-alice_fred')),
        );
        await t.pumpAndSettle();
        if (state == 'delete-question') {
          await t.tap(find.text('Delete on this phone'));
          await t.pumpAndSettle();
        }
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
        File('build/renders/chat-list-menu/${brightness.name}-$state.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!);
        // The test binding checks this is back before the body ends.
        debugDisableShadows = previousShadows;
      });
    }
  }
}

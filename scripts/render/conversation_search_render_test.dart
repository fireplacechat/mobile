// Search inside a conversation (issue 246), for review; not part of the
// byte-identical catalog. The profile's Search tile, the bar with a marked
// match, no matches, and frames of a jump to an old message.
//   TZ=UTC flutter test scripts/render/conversation_search_render_test.dart
//   python scripts/render/frames_to_gif.py build/frames/conversation-search
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/conversation_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} search', (t) async {
      final shadows = debugDisableShadows;
      debugDisableShadows = false;
      t.view.physicalSize = const Size(390, 780);
      t.view.devicePixelRatio = 1;
      t.view.padding = const FakeViewPadding(top: 47);
      addTearDown(t.view.reset);
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      for (var i = 0; i < 240; i++) {
        await f.chat.store.add(
          message(
            id: 'old$i',
            body: i == 0
                ? 'The garden lanterns are in the shed'
                : 'Earlier message $i',
            at: fixtureTime.subtract(Duration(days: 20, minutes: 240 - i)),
          ),
        );
      }
      final key = GlobalKey();
      await t.pumpWidget(
        ProviderScope(
          overrides: f.overrides,
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: fireplaceTheme(brightness),
              home: const ChatScreen(chatId: 'alice_fred'),
            ),
          ),
        ),
      );
      await settleUi(t);
      Future<void> shot(String path) async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            File('build/$path.png')
              ..createSync(recursive: true)
              ..writeAsBytesSync(data!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      final mode = brightness.name;
      await t.tap(find.byKey(const Key('chatDetails')));
      await t.pumpAndSettle();
      await shot('conversation-search/$mode-profile');
      await t.tap(find.byKey(const Key('profileSearch')));
      await t.pumpAndSettle();
      final field = find.byKey(const Key('conversationSearchField'));
      Future<void> search(String text) async {
        await t.enterText(field, text);
        await t.pump(ConversationSearch.debounce);
        await settleUi(t);
        await t.pumpAndSettle();
      }

      await search('zebra');
      await shot('conversation-search/$mode-none');
      await search('garden');
      await shot('conversation-search/$mode-match');
      // Step to the older match, past the history loaded at first.
      final older = find.byKey(const Key('conversationSearchOlder'));
      await t.tap(older);
      for (var i = 0; i < 14; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await t.pump(const Duration(milliseconds: 60));
        if (mode == 'light') {
          await shot(
            'frames/conversation-search/${i.toString().padLeft(3, '0')}',
          );
        }
      }
      await t.pumpAndSettle();
      await shot('conversation-search/$mode-older');
      debugDisableShadows = shadows;
    });
  }
}

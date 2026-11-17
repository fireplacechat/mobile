// Renders coming back to the chat list from a chat (issue 207) into
// build/renders/chat-list-return/, for review and for pull requests: the list
// scrolled down, the chat opened from it, and the list after Back.
//
//   TZ=UTC flutter test scripts/render/render_chat_list_return_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/widgets/page_return_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

/// Fictional people, newest conversation first.
const _people = [
  ('maya', 'See you at the station at nine'),
  ('jonas', 'The photos came out really well'),
  ('priya', 'Thanks for the recipe!'),
  ('leo', 'Running ten minutes late'),
  ('amara', 'Did you finish the book?'),
  ('tomas', 'Happy birthday!'),
  ('ines', 'I left the keys with Sam'),
  ('kai', 'Shall we try the new place on Friday?'),
  ('noor', 'Good luck tomorrow'),
  ('felix', 'That song is stuck in my head'),
  ('hana', 'The plants are watered'),
  ('oskar', 'Back home safe'),
  ('lucia', 'Can you send me the address?'),
  ('ravi', 'Ha, classic'),
];

Future<void> _seed(UiFixture f) async {
  f.chat.summaries = [
    for (final (i, (name, _)) in _people.indexed)
      ChatSummary(
        'alice_$name',
        name,
        fixtureTime.subtract(Duration(hours: 3 * i)),
      ),
  ];
  for (final (i, (name, body)) in _people.indexed) {
    await f.chat.store.add(
      LocalMessage(
        id: 'm$i',
        chatId: 'alice_$name',
        senderUid: name,
        senderDevice: 'example-device',
        outgoing: false,
        sentAt: fixtureTime.subtract(Duration(hours: 3 * i)),
        body: body,
      ),
    );
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('chat list return, ${brightness.name}', (t) async {
      await t.runAsync(loadFonts);
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final fixture = UiFixture();
      await _seed(fixture);
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
              navigatorObservers: [pageReturnObserver],
              home: const ChatListScreen(),
            ),
          ),
        ),
      );
      await settleUi(t);

      Future<void> shot(String name) async {
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
        File('build/renders/chat-list-return/${brightness.name}-$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!);
      }

      await t.drag(
        find.byKey(const Key('conversationList')),
        const Offset(0, -500),
      );
      await t.pumpAndSettle();
      await shot('1-scrolled');
      await t.tap(find.byKey(const ValueKey('conversation-alice_noor')));
      await t.pumpAndSettle();
      await settleUi(t);
      await shot('2-chat');
      await t.tap(find.byKey(const Key('chatBack')));
      await t.pumpAndSettle();
      await settleUi(t);
      await shot('3-back');
    });
  }
}

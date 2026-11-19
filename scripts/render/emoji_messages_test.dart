import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/groups/group_message_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final brightness in Brightness.values) {
    for (final state in [
      'received',
      'sent',
      'reply',
      'selected',
      'group',
      'large',
    ]) {
      testWidgets('${brightness.name} $state', (t) async {
        final originalShadows = debugDisableShadows;
        debugDisableShadows = false;
        try {
          t.view.physicalSize = Size(state == 'large' ? 320 : 390, 780);
          t.view.devicePixelRatio = 1;
          t.view.padding = const FakeViewPadding(top: 47);
          addTearDown(t.view.reset);
          final fixture = UiFixture();
          await fixture.seed();
          addTearDown(fixture.session.close);
          await fixture.chat.store.clearChat('alice_fred');
          const glyphs = ['🔥', '👋🏽🌷', '🌱🍎🌼', '🎈🎈🎈🎈'];
          for (var i = 0; i < glyphs.length; i++) {
            final msg = message(
              id: 'e$i',
              body: glyphs[i],
              outgoing: state == 'sent' || (state == 'reply' && i.isOdd),
              at: fixtureTime.add(Duration(minutes: i)),
            );
            await fixture.chat.store.add(
              state == 'reply' && i == 1
                  ? msg.copyWith(
                      quote: const MessageQuote(
                        targetId: 'e0',
                        senderUid: 'fred',
                        body: '🔥',
                      ),
                    )
                  : msg,
            );
          }
          if (state == 'reply') {
            await fixture.chat.react('alice_fred', 'e0', '❤️');
          }
          final key = GlobalKey();
          final theme = fireplaceTheme(brightness);
          await t.pumpWidget(
            ProviderScope(
              overrides: fixture.overrides,
              child: RepaintBoundary(
                key: key,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: theme.copyWith(
                    textTheme: theme.textTheme.apply(
                      fontFamily: 'Roboto',
                      fontFamilyFallback: const ['PreviewEmoji'],
                    ),
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(state == 'large' ? 2 : 1),
                    ),
                    child: child!,
                  ),
                  home: state == 'group'
                      ? Scaffold(
                          appBar: AppBar(title: const Text('Garden club')),
                          body: SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  for (var i = 0; i < glyphs.length; i++)
                                    GroupMessageRow(
                                      gid: 'garden',
                                      message: message(
                                        id: 'g$i',
                                        body: glyphs[i],
                                        outgoing: i.isOdd,
                                      ),
                                      color: ChatBubbleColor.forest,
                                      showName: true,
                                      showAvatar: true,
                                      actions: const [],
                                      onReactions: () {},
                                    ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : const ChatScreen(chatId: 'alice_fred'),
                ),
              ),
            ),
          );
          await settleUi(t);
          if (state == 'selected') {
            await t.longPress(find.byKey(const ValueKey('messageBubble-e0')));
            await t.pumpAndSettle();
            final select = find.byKey(const ValueKey('messageAction-select'));
            await t.ensureVisible(select);
            await t.tap(select);
            await t.pumpAndSettle();
          }
          expect(t.takeException(), isNull);
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          await t.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File('build/emoji-review/${brightness.name}-$state.png')
                ..createSync(recursive: true)
                ..writeAsBytesSync(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        } finally {
          debugDisableShadows = originalShadows;
        }
      });
    }
  }
}

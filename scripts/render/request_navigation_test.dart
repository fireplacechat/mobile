// Renders the real Requests, chat and chat-list routes through Accept and Back.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/model/chat/chat_summary.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

class _AcceptChat extends FixtureChat {
  final changes = StreamController<List<ChatSummary>>.broadcast();
  @override
  Stream<List<ChatSummary>> watchChats() async* {
    yield summaries;
    yield* changes.stream;
  }

  @override
  Future<void> acceptRequest(String chatId) async {
    summaries = [
      for (final chat in summaries)
        if (chat.chatId == chatId)
          ChatSummary(chatId, chat.peerUid, fixtureTime)
        else
          chat,
    ];
    changes.add(summaries);
  }
}

void main() {
  setUpAll(loadFonts);
  for (final mode in Brightness.values) {
    for (final large in [false, true]) {
      testWidgets('Accept and Back ${mode.name} large $large', (t) async {
        final prevShadows = debugDisableShadows;
        debugDisableShadows = false;
        try {
          final chat = _AcceptChat();
          final f = UiFixture(chat: chat);
          await f.seed();
          addTearDown(f.session.close);
          addTearDown(chat.changes.close);
          t.view.physicalSize = Size(large ? 320 : 390, 780);
          t.view.devicePixelRatio = 1;
          t.view.padding = const FakeViewPadding(top: 47);
          addTearDown(t.view.reset);
          final boundary = GlobalKey();
          final nav = GlobalKey<NavigatorState>();
          final theme = fireplaceTheme(mode);
          await t.pumpWidget(
            ProviderScope(
              overrides: f.overrides,
              child: RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                  navigatorKey: nav,
                  debugShowCheckedModeBanner: false,
                  theme: theme.copyWith(
                    platform: TargetPlatform.android,
                    textTheme: theme.textTheme.apply(
                      fontFamily: 'Roboto',
                      fontFamilyFallback: const ['PreviewEmoji'],
                    ),
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                    child: child!,
                  ),
                  home: const ChatListScreen(),
                ),
              ),
            ),
          );
          await settleUi(t);
          await t.ensureVisible(find.byKey(const Key('requestsTile')));
          await t.tap(find.byKey(const Key('requestsTile')));
          await t.pumpAndSettle();
          final accept = find.byKey(const Key('accept_alice_theo'));
          await t.ensureVisible(accept);
          await t.pumpAndSettle();
          final folder =
              'build/request-navigation/${mode.name}${large ? '-large' : ''}';
          Future<void> shot(String name) async {
            expect(t.takeException(), isNull);
            final render =
                boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            await t.runAsync(() async {
              final image = await render.toImage(pixelRatio: 2);
              try {
                final data = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                File('$folder/$name.png')
                  ..createSync(recursive: true)
                  ..writeAsBytesSync(data!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }

          await shot('00');
          await t.tap(accept);
          await t.pump();
          for (var i = 1; i <= 6; i++) {
            await t.pump(const Duration(milliseconds: 60));
            await shot('0$i');
          }
          await t.pumpAndSettle();
          await shot('07');
          nav.currentState!.pop();
          for (var i = 8; i <= 14; i++) {
            await t.pump(const Duration(milliseconds: 60));
            await shot(i.toString().padLeft(2, '0'));
          }
          await t.pumpAndSettle();
          await shot('15');
        } finally {
          debugDisableShadows = prevShadows;
        }
      });
    }
  }
}

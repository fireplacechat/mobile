// Every speech bubble round (the owner's rule), for review; not part of
// the byte-identical catalog. Each place a bubble icon appears: the empty
// chat list, New chat's "Message @name", a profile (Message and Report
// Spam), the in-app notifications row, and the chat row menu's Mark read.
// Runs on the branch before this change too, for the before images.
//   TZ=UTC flutter test scripts/render/round_bubbles_render_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/profile/person_profile_screen.dart';
import 'package:fireplace/src/view/settings/notification_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final brightness in Brightness.values) {
    for (final state in ['empty', 'new-chat', 'profile', 'notices', 'menu']) {
      testWidgets('${brightness.name} $state', (t) async {
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        t.view.physicalSize = const Size(390, 780);
        t.view.devicePixelRatio = 1;
        t.view.padding = const FakeViewPadding(top: 47);
        addTearDown(t.view.reset);
        final f = UiFixture();
        await f.seed();
        addTearDown(f.session.close);
        if (state == 'empty') f.chat.summaries = [];
        final key = GlobalKey();
        await t.pumpWidget(
          ProviderScope(
            overrides: f.overrides,
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: fireplaceTheme(brightness),
                home: switch (state) {
                  'profile' => PersonProfileScreen(
                    peerUid: 'fred',
                    name: 'fred',
                    inChat: ProfileChatHandlers(
                      chatId: 'alice_fred',
                      onMute: (_) async {},
                      onBlock: () async {},
                      onUnblock: () async {},
                      onReportSpam: (_) async {},
                    ),
                  ),
                  'notices' => const NotificationSettingsScreen(),
                  _ => const ChatListScreen(),
                },
              ),
            ),
          ),
        );
        await settleUi(t);
        if (state == 'new-chat') {
          await t.tap(find.byKey(const Key('newChat')));
          await t.pumpAndSettle();
          await t.enterText(find.byType(TextField).last, 'zoe');
          await t.pumpAndSettle();
        } else if (state == 'menu') {
          await t.longPress(
            find.byKey(const ValueKey('conversation-alice_fred')),
          );
          await t.pumpAndSettle();
        }
        await t.pumpAndSettle();
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            File('build/round-bubbles/${brightness.name}-$state.png')
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

// People are named by their name alone (issue 203). The "@" stays only where
// a username is typed (New chat's "Message @…") or shown as a username
// (Settings → Your username).
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

void main() {
  Future<UiFixture> open(WidgetTester t, Widget home) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: f.overrides,
        child: MaterialApp(theme: fireplaceTheme(Brightness.light), home: home),
      ),
    );
    await settleUi(t);
    return f;
  }

  testWidgets('New chat lists people by name; a typed username keeps its @', (
    t,
  ) async {
    await open(t, const ChatListScreen());
    await t.tap(find.byKey(const Key('newChat')));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('contact_fred')),
        matching: find.text('fred'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('@fred'), findsNothing);
    await t.enterText(find.byKey(const Key('peerUsername')), 'sam');
    await t.pump();
    expect(find.text('Message @sam'), findsOneWidget);
  });

  testWidgets('chat details are titled by the name alone', (t) async {
    await open(t, const ChatListScreen());
    await t.tap(find.byKey(const ValueKey('conversation-alice_fred')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('chatDetails')));
    await t.pumpAndSettle();
    expect(find.textContaining('@fred'), findsNothing);
    expect(find.text('fred'), findsWidgets);
  });

  testWidgets('Settings still shows your username with its @', (t) async {
    await open(t, const SettingsScreen());
    expect(find.text('@alice'), findsOneWidget);
  });
}

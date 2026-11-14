// The thin scroll bar (issue 165): on the chat list, a conversation and
// Settings; hidden at rest, shown while the list moves, and faded afterwards.
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/widgets/thin_scrollbar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

void main() {
  Future<void> pump(WidgetTester t, Widget home, {Size? size}) async {
    if (size != null) {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
    }
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
  }

  testWidgets('the chat list has the bar', (t) async {
    await pump(t, const ChatListScreen());
    expect(
      find.ancestor(
        of: find.byKey(const Key('conversationList')),
        matching: find.byType(ThinScrollbar),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a conversation has the bar, on its own scroll position', (
    t,
  ) async {
    await pump(t, const ChatScreen(chatId: 'alice_fred'));
    final bar = t.widget<ThinScrollbar>(
      find.ancestor(
        of: find.byKey(const Key('messageTimeline')),
        matching: find.byType(ThinScrollbar),
      ),
    );
    expect(
      bar.controller,
      t.widget<ListView>(find.byKey(const Key('messageTimeline'))).controller,
    );
  });

  testWidgets('Settings shows the thumb while it moves and fades it after', (
    t,
  ) async {
    // Short enough that Settings has to scroll.
    await pump(t, const SettingsScreen(), size: const Size(390, 500));
    final bar = find.byType(ThinScrollbar);
    expect(bar, findsOneWidget);
    // How visible the thumb is: 0 hidden, 1 fully shown.
    double thumb() =>
        (t
                    .widget<CustomPaint>(
                      find
                          .descendant(
                            of: bar,
                            matching: find.byType(CustomPaint),
                          )
                          .first,
                    )
                    .foregroundPainter!
                as ScrollbarPainter)
            .fadeoutOpacityAnimation
            .value;
    // Nothing drawn before the list moves.
    expect(thumb(), 0);
    final gesture = await t.startGesture(t.getCenter(find.byType(ListView)));
    // The first move is what the list recognises as a drag.
    await gesture.moveBy(const Offset(0, -40));
    await gesture.moveBy(const Offset(0, -120));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(thumb(), 1);
    expect(t.takeException(), isNull);
    await gesture.up();
    // It fades a moment after the list stops.
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(thumb(), 0);
    expect(find.byType(CupertinoScrollbar), findsOneWidget);
  });
}

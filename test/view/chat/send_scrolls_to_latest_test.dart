// REVIEW R03: after the USER sends a message, it must come into view, even if they had scrolled up
// to read older messages (every mainstream chat app does this). On b01a65d the timeline stays put.
import 'dart:async';

import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

Future<UiFixture> longChat(WidgetTester t) async {
  final f = UiFixture();
  for (var i = 0; i < 80; i++) {
    await f.chat.store.add(
      message(
        id: 'm${i.toString().padLeft(3, '0')}',
        body: 'older message number $i',
        outgoing: i.isEven,
        at: fixtureTime.subtract(Duration(minutes: 80 - i)),
      ),
    );
  }
  t.view.physicalSize = const Size(800, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        home: const ChatScreen(chatId: 'alice_fred'),
      ),
    ),
  );
  await settleUi(t);
  return f;
}

ScrollController timeline(WidgetTester t) =>
    t.widget<ListView>(find.byKey(const Key('messageTimeline'))).controller!;

void main() {
  testWidgets('sending while scrolled up scrolls to the sent message', (
    t,
  ) async {
    final f = await longChat(t);
    await t.drag(
      find.byKey(const Key('messageTimeline')),
      const Offset(0, 900),
    );
    await settleUi(t);
    expect(
      timeline(t).offset,
      greaterThan(96),
      reason: 'the user is reading older messages',
    );
    // Like the real service: the sent message is stored BEFORE sendText returns.
    f.chat.sendHold = Completer<void>();
    await t.enterText(find.byKey(const Key('composer')), 'my reply');
    await t.pump();
    await t.tap(find.byKey(const Key('send')));
    await t.pump();
    await f.chat.store.add(
      message(
        id: 'zz-new',
        body: 'my reply',
        outgoing: true,
        at: fixtureTime.add(const Duration(minutes: 1)),
      ),
    );
    await t.pump();
    f.chat.sendHold!.complete();
    await settleUi(t);
    for (var i = 0; i < 10; i++) {
      await t.pump(
        const Duration(milliseconds: 100),
      ); // allow a short scroll animation
    }
    expect(
      timeline(t).offset,
      lessThanOrEqualTo(96),
      reason: 'the sent message should now be visible',
    );
    expect(find.text('my reply'), findsWidgets);
  });

  testWidgets(
    'a message that ARRIVES while the user reads older ones does not move the view (existing behavior kept)',
    (t) async {
      final f = await longChat(t);
      await t.drag(
        find.byKey(const Key('messageTimeline')),
        const Offset(0, 900),
      );
      await settleUi(t);
      final before = timeline(t).offset;
      final anchor = find.text('older message number 40');
      final top = anchor.evaluate().isEmpty ? null : t.getTopLeft(anchor).dy;
      await f.chat.store.add(
        message(
          id: 'zz-in',
          body: 'incoming while reading',
          at: fixtureTime.add(const Duration(minutes: 1)),
        ),
      );
      await settleUi(t);
      expect(timeline(t).offset, greaterThan(96));
      expect(before, greaterThan(96));
      if (top != null) {
        expect(
          t.getTopLeft(anchor).dy,
          closeTo(top, 2),
          reason: 'the visible text stays put',
        );
      }
    },
  );
}

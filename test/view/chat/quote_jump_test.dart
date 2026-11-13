// Tapping a quote scrolls to the original and highlights it briefly, also
// when the original is already on screen.
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_route_observer.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/timeline_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

/// 30 messages, then fred's reply quoting [target] (one of mine).
Future<UiFixture> _chatQuoting(String target, String targetBody) async {
  final f = UiFixture();
  await f.seed();
  for (var i = 0; i < 30; i++) {
    await f.chat.store.add(
      message(
        id: 'm$i',
        body: 'Message $i',
        outgoing: i.isEven,
        at: fixtureTime.add(Duration(hours: 1, minutes: i)),
      ),
    );
  }
  await f.chat.store.add(
    message(
      id: 'reply',
      body: 'Yes, that one.',
      at: fixtureTime.add(const Duration(hours: 2)),
    ).copyWith(
      quote: MessageQuote(
        targetId: target,
        senderUid: 'alice',
        body: targetBody,
      ),
    ),
  );
  return f;
}

Future<void> _open(WidgetTester t, UiFixture f) async {
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        navigatorObservers: [chatRouteObserver],
        home: const ChatScreen(chatId: 'alice_fred'),
      ),
    ),
  );
  await settleUi(t);
  await t.pumpAndSettle();
}

Rect _view(WidgetTester t) =>
    t.getRect(find.byKey(const Key('messageTimeline')));
Rect _bubble(WidgetTester t, String id) =>
    t.getRect(find.byKey(ValueKey('messageBubble-$id')));

bool _flashing(WidgetTester t, String id) {
  final box = t.widget<AnimatedContainer>(
    find
        .ancestor(
          of: find.byKey(ValueKey('messageBubble-$id')),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return (box.decoration! as BoxDecoration).color!.a > 0;
}

ScrollController _scroll(WidgetTester t) =>
    t.widget<ListView>(find.byKey(const Key('messageTimeline'))).controller!;

Future<void> _tapQuote(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('messageQuote-reply')));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('a recent original on screen: it stays put and highlights', (
    t,
  ) async {
    final f = await _chatQuoting('m28', 'Message 28');
    await _open(t, f);
    expect(_scroll(t).offset, 0);
    final before = _bubble(t, 'm28');
    expect(_view(t).contains(before.center), isTrue);
    await _tapQuote(t);
    expect(_flashing(t, 'm28'), isTrue);
    // Near the newest messages there is no room to scroll it to the middle:
    // the view stays at the bottom and nothing overshoots.
    expect(_scroll(t).offset, lessThan(TimelineScroll.awayThreshold));
    expect(find.textContaining('Could not locate'), findsNothing);
    await t.pump(TimelineScroll.flashFor);
    await t.pumpAndSettle();
    expect(_flashing(t, 'm28'), isFalse);
  });

  testWidgets('an original visible at the top edge comes to the middle', (
    t,
  ) async {
    final f = await _chatQuoting('m24', 'Message 24');
    await _open(t, f);
    final view = _view(t);
    final before = _bubble(t, 'm24');
    // Peeking in at the top: partly on screen, partly cut off.
    expect(before.bottom, greaterThan(view.top));
    expect(before.top, lessThan(view.top));
    expect(before.center.dy - view.top, lessThan(view.height * .3));
    await _tapQuote(t);
    await t.pumpAndSettle();
    final after = _bubble(t, 'm24');
    expect((after.center.dy - view.center.dy).abs(), lessThan(40));
    expect(_flashing(t, 'm24'), isTrue);
  });

  testWidgets('a far original is scrolled to and highlighted', (t) async {
    final f = await _chatQuoting('m4', 'Message 4');
    await _open(t, f);
    expect(find.byKey(const ValueKey('messageBubble-m4')), findsNothing);
    await _tapQuote(t);
    await t.pumpAndSettle();
    final view = _view(t);
    expect((_bubble(t, 'm4').center.dy - view.center.dy).abs(), lessThan(40));
    expect(_flashing(t, 'm4'), isTrue);
  });
}

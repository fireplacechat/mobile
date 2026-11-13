// Opening a chat from a search result: the whole conversation, scrolled to
// the message, which is highlighted briefly. It used to show only the
// history up to the result, with no way to scroll past it.
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/view/chat/chat_route_observer.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/timeline_scroll.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

ProviderContainer _container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(ChatScreen)));

Future<void> _open(
  WidgetTester t,
  UiFixture f,
  String? messageId, {
  bool reducedMotion = false,
}) async {
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        navigatorObservers: [chatRouteObserver],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: ChatScreen(chatId: 'alice_fred', initialMessageId: messageId),
      ),
    ),
  );
  await settleUi(t);
}

/// A long conversation: the seeded five, then 40 newer ones.
Future<UiFixture> _longChat() async {
  final f = UiFixture();
  await f.seed();
  for (var i = 0; i < 40; i++) {
    await f.chat.store.add(
      message(
        id: 'later-$i',
        body: 'Later message $i',
        at: fixtureTime.add(Duration(hours: 1, minutes: i)),
      ),
    );
  }
  return f;
}

ScrollController _timeline(WidgetTester t) =>
    t.widget<ListView>(find.byKey(const Key('messageTimeline'))).controller!;

bool _flashing(WidgetTester t, String id) {
  final container = t.widget<AnimatedContainer>(
    find
        .ancestor(
          of: find.byKey(ValueKey('messageBubble-$id')),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  final color = (container.decoration! as BoxDecoration).color!;
  return color.a > 0;
}

void main() {
  testWidgets('jumps to the result and the rest of the chat scrolls', (
    t,
  ) async {
    final f = await _longChat();
    await _open(t, f, '1');
    await t.pumpAndSettle();
    expect(find.text('Are we still on for Saturday?'), findsOneWidget);
    final controller = _timeline(t);
    expect(controller.offset, greaterThan(0), reason: 'scrolled up to it');
    // No floor: scrolling down reaches the newest message.
    controller.jumpTo(0);
    await t.pumpAndSettle();
    expect(find.text('Later message 39'), findsOneWidget);
    expect(find.byKey(const Key('searchLocation')), findsNothing);
  });

  testWidgets('a result in the middle of a chat lands in the middle', (
    t,
  ) async {
    final f = await _longChat();
    await _open(t, f, 'later-20');
    await t.pumpAndSettle();
    final view = t.getRect(find.byKey(const Key('messageTimeline')));
    final bubble = t.getRect(
      find.byKey(const ValueKey('messageBubble-later-20')),
    );
    expect((bubble.center.dy - view.center.dy).abs(), lessThan(40));
  });

  testWidgets('the result is highlighted briefly, then not', (t) async {
    final f = await _longChat();
    await _open(t, f, '1');
    // settleUi has run the jump; the highlight is on until it times out.
    await t.pump(TimelineScroll.flashFor ~/ 2);
    expect(_flashing(t, '1'), isTrue);
    expect(_flashing(t, '2'), isFalse);
    await t.pump(TimelineScroll.flashFor);
    await t.pumpAndSettle();
    expect(_flashing(t, '1'), isFalse);
  });

  testWidgets('with reduced motion it jumps and highlights too', (t) async {
    final f = await _longChat();
    await _open(t, f, '1', reducedMotion: true);
    await t.pump();
    expect(find.text('Are we still on for Saturday?'), findsOneWidget);
    expect(_timeline(t).offset, greaterThan(0));
  });

  testWidgets('newer messages count as seen only once scrolled down to them', (
    t,
  ) async {
    final f = await _longChat();
    await _open(t, f, '1');
    final unread = _container(t).read(chatActivityProvider).unread;
    expect(unread['alice_fred'], greaterThan(0));
    _timeline(t).jumpTo(0);
    await t.pumpAndSettle();
    await settleUi(t);
    expect(_container(t).read(chatActivityProvider).unread['alice_fred'], 0);
  });

  testWidgets('a result no longer on this device says so', (t) async {
    final f = UiFixture();
    await f.seed();
    await _open(t, f, 'gone');
    expect(
      find.text('This search result is no longer on this device.'),
      findsOneWidget,
    );
    expect(find.text('Around two? There is no rush.'), findsOneWidget);
  });

  testWidgets('a short chat shows everything around the result', (t) async {
    final f = UiFixture();
    await f.seed();
    await _open(t, f, '1');
    await t.pumpAndSettle();
    expect(find.text('Are we still on for Saturday?'), findsOneWidget);
    expect(find.text('Around two? There is no rush.'), findsOneWidget);
  });
}

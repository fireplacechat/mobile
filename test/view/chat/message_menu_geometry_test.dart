import 'dart:math' as math;

import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/message_actions_overlay.dart';
import 'package:fireplace/src/view/chat/message_menu_stack.dart';
import 'package:fireplace/src/view/chat/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

const phone = Size(375, 812);
const safeArea = EdgeInsets.only(top: 44, bottom: 34);

Finder bubble(String id) => find.byKey(ValueKey('messageBubble-$id'));
Finder action(String id) => find.byKey(ValueKey('messageAction-$id'));
final lifted = find.byWidgetPredicate((w) => w is MessageBubble && w.preview);
final bar = find.byKey(const Key('messageReactionBar'));
final panel = find.byKey(const Key('messageActionsPanel'));

Future<void> openChat(
  WidgetTester t,
  UiFixture f, {
  Widget? home,
  bool reduceMotion = false,
}) async {
  t.view.physicalSize = phone;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: safeArea,
            viewPadding: safeArea,
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: home ?? const ChatScreen(chatId: 'alice_fred'),
      ),
    ),
  );
  await settleUi(t);
}

/// Enough history that early messages sit high on the screen.
Future<UiFixture> longChat() async {
  final f = UiFixture();
  await f.seed();
  for (var i = 0; i < 8; i++) {
    await f.chat.store.add(
      message(
        id: 'more-$i',
        body: 'Message number $i',
        outgoing: i.isOdd,
        at: fixtureTime.add(Duration(minutes: i + 1)),
      ),
    );
  }
  return f;
}

ScrollPosition timeline(WidgetTester t) =>
    Scrollable.of(t.element(bubble('more-7'))).position;

void main() {
  testWidgets('bar, message and actions use the measured geometry', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();

    final reactions = t.getRect(bar);
    final message = t.getRect(lifted);
    final menu = t.getRect(panel);
    expect(reactions.left, MessageMenuMetrics.edge);
    expect(reactions.size, const Size(343, 56));
    expect(message.top - reactions.bottom, moreOrLessEquals(12, epsilon: 4.5));
    expect(menu.width, 250);
    expect(menu.left, MessageMenuMetrics.edge);
    // Seven 48-point targets scroll inside the available width.
    final heart = t.getRect(action('react-❤️'));
    final more = t.getRect(action('moreReactions'));
    expect(heart.left - reactions.left, 6);
    expect(heart.width, 48);
    expect(more.right, lessThanOrEqualTo(reactions.right));
    // Each row is the body line plus Signal's 23-point padding.
    final reply = t.getRect(action('reply'));
    final forward = t.getRect(action('forward'));
    expect(
      forward.top - reply.top,
      moreOrLessEquals(MessageMenuMetrics.rowHeight, epsilon: .01),
    );
    expect(reply.width, moreOrLessEquals(menu.width, epsilon: .01));
    expect(reply.right, moreOrLessEquals(menu.right, epsilon: .01));
    expect(menu.bottom, phone.height - safeArea.bottom);
    expect(
      t.widget<Material>(panel).borderRadius,
      BorderRadius.circular(MessageMenuMetrics.menuRadius),
    );
  });

  testWidgets('an outgoing message hangs its bar and actions from the right', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await t.longPress(bubble('4'));
    await t.pumpAndSettle();
    expect(t.getRect(bar).right, phone.width - MessageMenuMetrics.edge);
    expect(t.getRect(panel).right, phone.width - MessageMenuMetrics.edge);
  });

  testWidgets('a message with room below stays exactly where it was held', (
    t,
  ) async {
    final f = await longChat();
    addTearDown(f.session.close);
    await openChat(t, f);
    // The first message high enough for the bar above and the list below.
    final target = [for (var i = 0; i < 8; i++) bubble('more-$i')].firstWhere(
      (b) =>
          b.evaluate().isNotEmpty &&
          t.getRect(b).top > safeArea.top + 16 + 56 + 12 + 64,
    );
    final before = t.getRect(target);
    expect(before.top, greaterThan(safeArea.top + 16 + 56 + 12));
    expect(before.bottom + 12 + 350, lessThan(phone.height - safeArea.bottom));
    final offset = timeline(t).pixels;

    await t.longPress(target);
    await t.pump(const Duration(milliseconds: 60));
    final early = t.getRect(lifted);
    await t.pumpAndSettle();
    final settled = t.getRect(lifted);

    expect(early.top, moreOrLessEquals(settled.top, epsilon: .01));
    expect(settled.left, before.left);
    expect(settled.top, moreOrLessEquals(before.top, epsilon: 4.5));
    expect(t.getRect(bar).bottom, lessThan(settled.top));
    expect(t.getRect(panel).top, greaterThan(settled.bottom));
    expect(timeline(t).pixels, offset);
    expect(t.getRect(target), before);
  });

  testWidgets(
    'a message too low for its actions rises, then returns on dismissal',
    (t) async {
      final f = await longChat();
      addTearDown(f.session.close);
      await openChat(t, f);
      final target = bubble('more-7');
      final before = t.getRect(target);
      final offset = timeline(t).pixels;
      expect(before.bottom + 12 + 300, greaterThan(phone.height));

      await t.longPress(target);
      await t.pump(const Duration(milliseconds: 30));
      final start = t.getRect(lifted).top;
      await t.pumpAndSettle();
      final raised = t.getRect(lifted);

      // It moved up, by animation, only as far as the list needs.
      expect(raised.top, lessThan(start));
      expect(start, lessThanOrEqualTo(before.top + 5));
      expect(t.getRect(panel).bottom, phone.height - safeArea.bottom);
      expect(
        t.getRect(panel).top - raised.bottom,
        moreOrLessEquals(12, epsilon: 4.5),
      );
      // The conversation underneath did not scroll or move.
      expect(timeline(t).pixels, offset);
      expect(t.getRect(target), before);

      await t.tapAt(const Offset(350, 60));
      await t.pump();
      await t.pump(const Duration(milliseconds: 330));
      final returning = t.getRect(lifted).top;
      expect(returning, greaterThan(raised.top));
      await t.pumpAndSettle();
      expect(lifted, findsNothing);
      expect(timeline(t).pixels, offset);
      expect(t.getRect(target), before);
    },
  );

  testWidgets('reacting to a raised message leaves the conversation in place', (
    t,
  ) async {
    final f = await longChat();
    addTearDown(f.session.close);
    await openChat(t, f);
    final offset = timeline(t).pixels;
    final above = t.getRect(bubble('more-5'));
    await t.longPress(bubble('more-7'));
    await t.pumpAndSettle();
    await t.tap(action('react-👍'));
    await t.pumpAndSettle();
    expect(f.chat.reactions, [('more-7', '👍')]);
    expect(lifted, findsNothing);
    expect(timeline(t).pixels, offset);
    expect(t.getRect(bubble('more-5')).left, above.left);
  });

  testWidgets('a tall message scales so the actions stay on screen', (t) async {
    final f = UiFixture();
    await f.seed();
    await f.chat.store.add(
      message(
        id: 'tall',
        outgoing: true,
        at: fixtureTime.add(const Duration(minutes: 5)),
        body: List.filled(80, 'A line of message text.').join(' '),
      ),
    );
    addTearDown(f.session.close);
    await openChat(t, f);
    final rect = t.getRect(bubble('tall'));
    final y = math.min(rect.bottom - 24, phone.height - 120);
    await t.longPressAt(
      Offset(rect.center.dx, y.clamp(120, phone.height - 80)),
    );
    await t.pumpAndSettle();
    final menu = t.getRect(panel);
    expect(menu.top, greaterThanOrEqualTo(safeArea.top));
    expect(menu.bottom, lessThanOrEqualTo(phone.height - safeArea.bottom));
    expect(
      t
          .renderObject<RenderMessageMenu>(find.byType(MessageMenuStack))
          .previewScale,
      lessThan(1),
    );
  });

  testWidgets('reduced motion places the raised message without animating', (
    t,
  ) async {
    final f = await longChat();
    addTearDown(f.session.close);
    await openChat(t, f, reduceMotion: true);
    await t.longPress(bubble('more-7'));
    await t.pump();
    await t.pump();
    expect(t.getRect(panel).bottom, phone.height - safeArea.bottom);
  });

  testWidgets('Back still returns to the list after the menu has closed', (
    t,
  ) async {
    // The menu registers a Back handler while open. Removing it must not
    // tell Android that Back now leaves the app from inside a chat.
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final handles = <bool>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          handles.add(call.arguments as bool);
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(
      t,
      f,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const Key('open'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ChatScreen(chatId: 'alice_fred'),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('open')));
    await t.pumpAndSettle();
    await settleUi(t);
    expect(handles.last, isTrue);

    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    await t.tap(action('reply'));
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(handles.last, isTrue, reason: 'still inside a chat');

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byKey(const Key('open')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

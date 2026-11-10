import 'package:fireplace/src/view/chat/message_menu_parts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'long_press_menu_test.dart' show openChat, bubble, action;

void main() {
  testWidgets(
    'back closes the overlay and a deleted message cannot be copied',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await openChat(t, f);
      await t.longPress(bubble('5'));
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(action('copy'), findsNothing);
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
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
      await t.longPress(bubble('4'));
      await t.pumpAndSettle();
      await f.chat.deleteForEveryone('alice_fred', '4');
      await t.pumpAndSettle();
      expect(
        find.text('Looking forward to it. What time works for you?'),
        findsNothing,
      );
      expect(bubble('4'), findsNothing);
      expect(action('copy'), findsNothing);
      expect(copied, isNull);
    },
  );
  for (final id in ['4', '5']) {
    testWidgets('held bubble $id stays aligned with its menu', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await openChat(t, f);
      await t.longPress(bubble(id));
      await t.pumpAndSettle();
      final held = t.getRect(find.byKey(ValueKey('heldMessage-$id')));
      final panel = t.getRect(find.byKey(const Key('messageActionsPanel')));
      expect(panel.top, greaterThanOrEqualTo(held.bottom));
      expect(
        id == '4' ? panel.right : panel.left,
        closeTo(id == '4' ? held.right : held.left, 1),
      );
      expect(panel.bottom, lessThanOrEqualTo(844 - 12));
      // The chat behind the focus is blurred. The menu panel is solid.
      expect(find.byType(BackdropFilter), findsOneWidget);
      await t.tapAt(const Offset(380, 30));
      await t.pumpAndSettle();
      expect(action('copy'), findsNothing);
      expect(find.byKey(ValueKey('heldMessage-$id')), findsNothing);
    });
  }

  testWidgets('the held message is not underlined', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    final texts = t.widgetList<RichText>(
      find.descendant(
        of: find.byKey(const ValueKey('heldMessage-5')),
        matching: find.byType(RichText),
      ),
    );
    expect(texts, isNotEmpty);
    for (final rich in texts) {
      expect(
        rich.text.style?.decoration,
        anyOf(isNull, TextDecoration.none),
        reason: rich.text.toPlainText(),
      );
    }
  });

  testWidgets('holding a reaction enlarges it and releasing sends it', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    final emoji = find.descendant(
      of: action('react-❤️'),
      matching: find.text('❤️'),
    );
    final resting = t.getRect(emoji);
    final gesture = await t.startGesture(t.getCenter(action('react-❤️')));
    // The grow starts during this frame, so the first tick is the next one.
    await t.pump();
    expect((t.getRect(emoji).center - resting.center).dy.abs(), lessThan(1));
    await t.pump(const Duration(milliseconds: 80));
    final mid = resting.center.dy - t.getRect(emoji).center.dy;
    await t.pump(const Duration(milliseconds: 200));
    final focused = t.getRect(emoji);
    expect(mid, greaterThan(4));
    expect(mid, lessThan(34));
    expect(resting.center.dy - focused.center.dy, closeTo(36, 1.5));
    expect(focused.height / resting.height, closeTo(1.5, 0.05));
    expect(action('react-❤️'), findsOneWidget);
    await gesture.up();
    await t.pumpAndSettle();
    expect(f.chat.reactions, [('5', '❤️')]);
  });

  testWidgets('holding a row fills it and releasing selects it', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    final reply = action('reply');
    final gesture = await t.startGesture(t.getCenter(reply));
    await t.pump();
    expect(
      t
          .widget<ColoredBox>(
            find.ancestor(of: reply, matching: find.byType(ColoredBox)).first,
          )
          .color,
      MessageMenuMetrics.rowHighlight,
    );
    await gesture.moveTo(t.getCenter(action('copy')));
    await t.pump();
    expect(
      t
          .widget<ColoredBox>(
            find
                .ancestor(of: action('copy'), matching: find.byType(ColoredBox))
                .first,
          )
          .color,
      MessageMenuMetrics.rowHighlight,
    );
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
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
    await gesture.up();
    await t.pumpAndSettle();
    expect(action('reply'), findsNothing);
    expect(copied, 'Around two? There is no rush.');
  });

  testWidgets('releasing a row press outside the menu leaves it open', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    final panel = t.getRect(find.byKey(const Key('messageActionsPanel')));
    final gesture = await t.startGesture(t.getCenter(action('reply')));
    await t.pump();
    await gesture.moveTo(Offset(panel.left - 40, panel.center.dy));
    await t.pump();
    expect(
      t
          .widget<ColoredBox>(
            find
                .ancestor(
                  of: action('reply'),
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color,
      Colors.transparent,
    );
    await gesture.up();
    await t.pumpAndSettle();
    expect(action('reply'), findsOneWidget);
    expect(f.chat.reactions, isEmpty);
  });

  testWidgets('a focused emoji shrinks again when the finger leaves it', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    final emoji = find.descendant(
      of: action('react-❤️'),
      matching: find.text('❤️'),
    );
    final resting = t.getRect(emoji);
    final gesture = await t.startGesture(t.getCenter(action('react-❤️')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(resting.center.dy - t.getRect(emoji).center.dy, closeTo(36, 1.5));
    await gesture.moveTo(
      t.getCenter(find.byKey(const Key('messageActionsPanel'))),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(
      (t.getRect(emoji).center.dy - resting.center.dy).abs(),
      lessThan(1.5),
    );
    await gesture.up();
    await t.pumpAndSettle();
    expect(f.chat.reactions, isEmpty);
    expect(action('reply'), findsOneWidget);
  });

  testWidgets('a small movement keeps the menu open', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    final gesture = await t.startGesture(t.getCenter(bubble('5')));
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 1));
    await t.pumpAndSettle();
    await gesture.moveBy(const Offset(4, 4));
    await t.pump();
    await gesture.up();
    await t.pumpAndSettle();
    expect(action('copy'), findsOneWidget);
  });

  testWidgets('sliding off the actions and releasing closes the menu', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    final gesture = await t.startGesture(t.getCenter(bubble('5')));
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 1));
    await t.pumpAndSettle();
    await gesture.moveTo(const Offset(180, 30));
    await t.pump();
    await gesture.up();
    await t.pumpAndSettle();
    expect(action('copy'), findsNothing);
  });

  testWidgets('context-menu key opens actions and Escape dismisses them', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    Focus.of(t.element(bubble('5'))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await t.pumpAndSettle();
    expect(action('copy'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(action('copy'), findsNothing);
  });
}

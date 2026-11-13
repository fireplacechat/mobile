import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/view/chat/message_menu_parts.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';

import '../../support/ui_fixture.dart';
import 'long_press_menu_test.dart' show openChat, bubble, action;

void main() {
  testWidgets(
    'hold, slide to an emoji and release reacts without another tap',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await openChat(t, f);
      final gesture = await t.startGesture(t.getCenter(bubble('5')));
      await t.pump(kLongPressTimeout + const Duration(milliseconds: 1));
      await t.pumpAndSettle();
      final emoji = find.descendant(
        of: action('react-❤️'),
        matching: find.text('❤️'),
      );
      final resting = t.getRect(emoji);
      await gesture.moveTo(t.getCenter(action('react-❤️')));
      await t.pump();
      await t.pump(MessageMenuGesture.reactionDelay);
      // The grow starts on the frame after the delay.
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      final focused = t.getRect(emoji);
      expect(resting.center.dy - focused.center.dy, closeTo(36, 1.5));
      expect(
        focused.height / resting.height,
        closeTo(MessageMenuMetrics.reactionFocusScale, 0.05),
      );
      await gesture.up();
      await t.pumpAndSettle();
      expect(f.chat.reactions, [('5', '❤️')]);
      expect(action('react-❤️'), findsNothing);
    },
  );
  testWidgets('quick reaction, replace and remove through reaction details', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('messageReactionBar')), findsOneWidget);
    await t.tap(action('react-❤️'));
    await t.pumpAndSettle();
    expect(f.chat.reactions, [('5', '❤️')]);
    expect(find.byKey(const ValueKey('reaction-5-❤️')), findsOneWidget);
    final chip = t.getRect(find.byKey(const ValueKey('reaction-5-❤️')));
    final glyph = t.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('reaction-5-❤️')),
        matching: find.text('❤️'),
      ),
    );
    final message = t.getRect(bubble('5'));
    expect(chip.top, lessThan(message.bottom));
    expect(chip.bottom, greaterThan(message.bottom));
    // The pill is the emoji's square plus the same padding on both sides.
    expect(chip.height, closeTo(26, 0.5));
    expect(chip.width, closeTo(31, 0.5));
    expect(glyph.center.dx, closeTo(chip.center.dx, 0.5));
    expect(glyph.center.dy, closeTo(chip.center.dy, 2));
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    await t.tap(action('react-👍'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('reaction-5-❤️')), findsNothing);
    await t.tap(find.byKey(const ValueKey('reaction-5-👍')));
    await t.pumpAndSettle();
    await t.tap(find.text('You'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('reaction-5-👍')), findsNothing);
  });

  testWidgets('expanded picker sends one selected emoji', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    final bar = t.getRect(find.byKey(const Key('messageReactionBar')));
    final more = t.getRect(action('moreReactions'));
    // The button fills the bar's height, so compare with shared edges.
    expect(bar.expandToInclude(more), bar);
    await t.tap(action('moreReactions'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('pickReaction-🥰')));
    await t.pumpAndSettle();
    expect(f.chat.reactions, [('5', '🥰')]);
  });

  testWidgets('large text keeps picker emoji within their touch targets', (
    t,
  ) async {
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    await t.ensureVisible(action('moreReactions'));
    await t.tap(action('moreReactions'));
    await t.pumpAndSettle();
    final button = t.getSize(find.byKey(const ValueKey('pickReaction-🥰')));
    final emoji = t.getSize(find.text('🥰'));
    expect(emoji.height, lessThanOrEqualTo(button.height));
    expect(emoji.width, lessThanOrEqualTo(button.width));
    await t.tap(find.byKey(const ValueKey('pickReaction-🥰')));
    await t.pumpAndSettle();
    expect(f.chat.reactions, [('5', '🥰')]);
  });

  testWidgets('remote deletion confirms, cancels and the message disappears', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    Future<void> openDelete() async {
      await t.longPress(bubble('4'));
      await t.pumpAndSettle();
      await t.ensureVisible(action('delete'));
      await t.tap(action('delete'));
      await t.pumpAndSettle();
    }

    await openDelete();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(f.chat.remoteDeletes, isEmpty);
    await openDelete();
    await t.ensureVisible(find.byKey(const Key('confirmRemoteDelete')));
    await t.tap(find.byKey(const Key('confirmRemoteDelete')));
    await t.pumpAndSettle();
    expect(f.chat.remoteDeletes, ['4']);
    expect(find.text('This message was deleted'), findsNothing);
    expect(bubble('4'), findsNothing);
    expect(
      find.text('Looking forward to it. What time works for you?'),
      findsNothing,
    );
  });

  testWidgets('unknown reaction outcome says nothing and is not retried', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    f.chat.controlError = SendNotConfirmedException(
      outcome: SendOutcome.publishUnknown,
      chatId: 'alice_fred',
      messageId: 'event',
      body: '',
      attemptedAt: fixtureTime,
      persisted: true,
    );
    await openChat(t, f);
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    await t.tap(action('react-❤️'));
    await t.pumpAndSettle();
    expect(find.textContaining('It may have reached them'), findsNothing);
    expect(find.text('Check status'), findsNothing);
    expect(find.byKey(const ValueKey('reaction-5-❤️')), findsNothing);
    expect(f.chat.reactions, isEmpty);
    expect(f.chat.controlAttempts, 1);
  });

  testWidgets('a reaction shows at once, before its send finishes', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    f.chat.controlHold = Completer<void>();
    await openChat(t, f);
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    await t.tap(action('react-❤️'));
    await t.pumpAndSettle();
    expect(f.chat.reactions, isEmpty, reason: 'still sending');
    expect(find.byKey(const ValueKey('reaction-5-❤️')), findsOneWidget);
    f.chat.controlHold!.complete();
    await t.pumpAndSettle();
    expect(f.chat.reactions, [('5', '❤️')]);
    expect(find.byKey(const ValueKey('reaction-5-❤️')), findsOneWidget);
  });

  testWidgets('a reaction that fails is quietly gone', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    f.chat.controlHold = Completer<void>();
    f.chat.controlError = ChatException('Reaction refused for this test.');
    await openChat(t, f);
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    await t.tap(action('react-❤️'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('reaction-5-❤️')), findsOneWidget);
    f.chat.controlHold!.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('reaction-5-❤️')), findsNothing);
    expect(find.textContaining('Reaction refused'), findsNothing);
  });
}

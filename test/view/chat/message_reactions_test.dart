import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
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
      await gesture.moveTo(t.getCenter(action('react-❤️')));
      await t.pump();
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
    await t.ensureVisible(action('moreReactions'));
    await t.tap(action('moreReactions'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('pickReaction-🥰')));
    await t.pumpAndSettle();
    expect(f.chat.reactions, [('5', '🥰')]);
  });

  testWidgets(
    'remote deletion confirms, cancels and leaves a neutral placeholder',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await openChat(t, f);
      Future<void> openDelete() async {
        await t.longPress(bubble('4'));
        await t.pumpAndSettle();
        await t.ensureVisible(action('deleteEveryone'));
        await t.tap(action('deleteEveryone'));
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
      expect(find.text('This message was deleted'), findsOneWidget);
      await t.longPress(bubble('4'));
      await t.pumpAndSettle();
      expect(action('copy'), findsNothing);
      expect(find.byKey(const Key('messageReactionBar')), findsNothing);
    },
  );

  testWidgets('unknown reaction outcome offers a check and does not retry', (
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
    expect(find.textContaining('It may have reached them'), findsOneWidget);
    expect(find.text('Check status'), findsOneWidget);
    expect(f.chat.reactions, isEmpty);
    expect(f.chat.controlAttempts, 1);
  });
}

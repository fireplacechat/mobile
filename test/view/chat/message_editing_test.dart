import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/db/message_mutation.dart';

import '../../support/ui_fixture.dart';
import 'long_press_menu_test.dart' show openChat, bubble, action;

Future<void> edit(WidgetTester t) async {
  await t.longPress(bubble('4'));
  await t.pumpAndSettle();
  await t.ensureVisible(action('edit'));
  await t.tap(action('edit'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'editing has a separate draft and cancel restores ordinary composition',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await openChat(t, f);
      await t.enterText(find.byKey(const Key('composer')), 'Unsent reply');
      await t.pump();
      await edit(t);
      expect(find.byKey(const Key('editComposerPreview')), findsOneWidget);
      expect(
        t.widget<TextField>(find.byKey(const Key('composer'))).controller!.text,
        contains('Looking forward'),
      );
      await t.enterText(find.byKey(const Key('composer')), 'Changed');
      await t.tap(find.byKey(const Key('cancelEdit')));
      await t.pumpAndSettle();
      expect(find.text('Unsent reply'), findsOneWidget);
      expect(f.chat.edits, isEmpty);
    },
  );
  testWidgets('double tap, keyboard save, Edited history and live deletion', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await t.tap(bubble('4'));
    await t.pump(const Duration(milliseconds: 80));
    await t.tap(bubble('4'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('editComposerPreview')), findsOneWidget);
    expect(
      t.widget<IconButton>(find.byKey(const Key('send'))).onPressed,
      isNull,
    );
    await t.enterText(find.byKey(const Key('composer')), 'See you at three.');
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(f.chat.edits, [('4', 'See you at three.')]);
    expect(find.byKey(const Key('editComposerPreview')), findsNothing);
    await t.tap(find.byKey(const ValueKey('edited-4')));
    await t.pump(const Duration(milliseconds: 350));
    await t.pumpAndSettle();
    expect(find.text('Edit history'), findsOneWidget);
    expect(find.text('Original message'), findsOneWidget);
    expect(find.text('Current version'), findsOneWidget);
    await f.chat.deleteForEveryone('alice_fred', '4');
    await t.pumpAndSettle();
    expect(find.text('This message is no longer available.'), findsOneWidget);
    expect(find.text('Current version'), findsNothing);
  });
  testWidgets('uncertain edit leaves explicit recovery and does not retry', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    f.chat.controlError = SendNotConfirmedException(
      outcome: SendOutcome.publishUnknown,
      chatId: 'alice_fred',
      messageId: 'edit-pending',
      body: '',
      attemptedAt: fixtureTime,
      persisted: true,
      mutation: const MessageMutation(
        kind: MessageMutationKind.edit,
        targetId: '4',
        body: 'Changed',
        revision: 1,
      ),
    );
    await edit(t);
    await t.enterText(find.byKey(const Key('composer')), 'Changed');
    await t.pump();
    await t.tap(find.byKey(const Key('send')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('editComposerPreview')), findsNothing);
    expect(find.text('Check status'), findsOneWidget);
    expect(f.chat.controlAttempts, 1);
  });
  testWidgets('received and exhausted messages do not offer editing', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    final own = await f.chat.store.get('alice_fred', '4');
    await f.chat.store.add(own!.copyWith(editClock: 10));
    await openChat(t, f);
    for (final id in ['4', '5']) {
      await t.longPress(bubble(id));
      await t.pumpAndSettle();
      expect(action('edit'), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
    }
  });
}

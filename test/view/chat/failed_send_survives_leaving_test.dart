// A message that could not be sent is kept above the conversation screen, so
// leaving the chat neither loses it nor sends it again.
import 'dart:async';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

Future<void> pumpHome(WidgetTester t, UiFixture f) async {
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ChatScreen(chatId: 'alice_fred'),
                ),
              ),
              child: const Text('Open chat'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> openChat(WidgetTester t) async {
  await t.tap(find.text('Open chat'));
  await t.pumpAndSettle();
  await settleUi(t);
}

String composer(WidgetTester t) =>
    t.widget<TextField>(find.byKey(const Key('composer'))).controller!.text;

void main() {
  testWidgets(
    'a send that fails after leaving the chat is waiting there on return',
    (t) async {
      final f = UiFixture();
      await f.seed();
      await pumpHome(t, f);
      await openChat(t);
      f.chat.sendHold = Completer<void>();
      await t.enterText(
        find.byKey(const Key('composer')),
        'A long message I do not want to lose',
      );
      await t.pump();
      await t.tap(find.byKey(const Key('send')));
      await t.pump();
      expect(composer(t), isEmpty);
      expect(find.text('Sending…'), findsOneWidget);

      // Leave while it is still on its way, then it is refused.
      await t.tap(find.byKey(const Key('chatBack')));
      await t.pumpAndSettle();
      f.chat
        ..sendError = ChatException('Nothing was sent. Try again later.')
        ..sendHold!.complete();
      await settleUi(t);
      f.chat
        ..sendError = null
        ..sendHold = null;

      await openChat(t);
      expect(composer(t), isEmpty, reason: 'not restored as a draft');
      expect(find.text('A long message I do not want to lose'), findsOneWidget);
      expect(find.text('Not sent. Tap for options.'), findsOneWidget);
      expect(f.chat.sends, hasLength(1), reason: 'not sent again unasked');

      await t.tap(find.text('Not sent. Tap for options.'));
      await t.pumpAndSettle();
      expect(find.text('Nothing was sent. Try again later.'), findsOneWidget);
      await t.tap(find.byKey(const Key('failedSendAgain')));
      await settleUi(t);
      expect(f.chat.sends, hasLength(2));
      expect(find.text('Not sent. Tap for options.'), findsNothing);
    },
  );

  testWidgets('a bubble that is not in the history yet has no message menu', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await pumpHome(t, f);
    await openChat(t);
    f.chat.sendHold = Completer<void>();
    await t.enterText(find.byKey(const Key('composer')), 'On its way');
    await t.pump();
    await t.tap(find.byKey(const Key('send')));
    await t.pump();
    await t.longPress(find.text('On its way'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('messageAction-reply')), findsNothing);
    // Tapping a message that is still being sent offers nothing either.
    await t.tap(find.text('On its way'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('failedSendDialog')), findsNothing);
    f.chat.sendHold!.complete();
    await settleUi(t);
    expect(t.takeException(), isNull);
  });
}

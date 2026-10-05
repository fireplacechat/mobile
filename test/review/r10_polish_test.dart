// REVIEW R10: two small clarity fixes found in the renders.
//  a) the request banner's buttons sit tight against its text;
//  b) a chat whose last outgoing message is "not confirmed" previews as an ordinary sent message in the list.
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/ui/chat_list_screen.dart';
import 'package:fireplace/src/ui/chat_screen.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets(
    'request banner: at least 8 dp between the explanation and the buttons',
    (t) async {
      final f = UiFixture();
      f.chat.summaries = [
        ChatSummary(
          'alice_theo',
          'theo',
          fixtureTime,
          initiator: 'theo',
          accepted: false,
        ),
      ];
      addTearDown(f.session.close);
      await t.pumpWidget(
        ProviderScope(
          overrides: f.overrides,
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: const ChatScreen(chatId: 'alice_theo'),
          ),
        ),
      );
      await settleUi(t);
      final text = find.descendant(
        of: find.byKey(const Key('requestBanner')),
        matching: find.textContaining('wants to chat'),
      );
      final textBottom = t.getBottomLeft(text).dy;
      final buttonsTop = t
          .getTopLeft(find.byKey(const Key('acceptRequest')))
          .dy;
      expect(
        buttonsTop - textBottom,
        greaterThanOrEqualTo(8),
        reason: 'gap ${(buttonsTop - textBottom).toStringAsFixed(1)} dp',
      );
    },
  );

  testWidgets(
    'chat list: an unconfirmed last message is not previewed like a delivered one',
    (t) async {
      final f = UiFixture();
      f.chat.summaries = [ChatSummary('alice_fred', 'fred', fixtureTime)];
      await f.chat.store.add(
        message(
          id: '1',
          body: 'Are you there?',
          outgoing: true,
          status: MessageStatus.unconfirmed,
        ),
      );
      addTearDown(f.session.close);
      await t.pumpWidget(
        ProviderScope(
          overrides: f.overrides,
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: const ChatListScreen(),
          ),
        ),
      );
      await settleUi(t);
      final tile = find.byKey(const ValueKey('conversation-alice_fred'));
      expect(
        find.descendant(
          of: tile,
          matching: find.textContaining('Are you there?'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.textContaining('not confirmed'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'chat list: a delivered message is previewed as before (no warning wording)',
    (t) async {
      final f = UiFixture();
      f.chat.summaries = [ChatSummary('alice_fred', 'fred', fixtureTime)];
      await f.chat.store.add(
        message(id: '1', body: 'All good', outgoing: true),
      );
      addTearDown(f.session.close);
      await t.pumpWidget(
        ProviderScope(
          overrides: f.overrides,
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: const ChatListScreen(),
          ),
        ),
      );
      await settleUi(t);
      final tile = find.byKey(const ValueKey('conversation-alice_fred'));
      expect(
        find.descendant(
          of: tile,
          matching: find.textContaining('You: All good'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.textContaining('not confirmed'),
        ),
        findsNothing,
      );
    },
  );
}

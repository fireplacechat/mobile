import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  testWidgets('one to three emoji lose the bubble, four and replies keep it', (
    t,
  ) async {
    final fixture = UiFixture();
    await fixture.seed();
    addTearDown(fixture.session.close);
    for (var i = 1; i <= 5; i++) {
      final m = message(
        id: 'emoji$i',
        body: '🔥' * (i == 5 ? 1 : i),
        outgoing: i.isEven,
        at: fixtureTime.add(Duration(minutes: i)),
      );
      await fixture.chat.store.add(
        i == 5
            ? m.copyWith(
                quote: const MessageQuote(
                  targetId: 'emoji1',
                  senderUid: 'fred',
                  body: '🔥',
                ),
              )
            : m,
      );
    }
    await t.pumpWidget(
      ProviderScope(
        overrides: fixture.overrides,
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const ChatScreen(chatId: 'alice_fred'),
        ),
      ),
    );
    await settleUi(t);
    Finder bubble(int n) => find.byKey(ValueKey('messageBubble-emoji$n'));
    for (var i = 1; i <= 5; i++) {
      await t.ensureVisible(bubble(i));
      expect(
        t.widget<Container>(bubble(i)).decoration,
        i <= 3 ? isNull : isNotNull,
      );
      if (i != 4) {
        final text = t.widget<Text>(
          find
              .descendant(
                of: bubble(i),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Text &&
                      w.data == '🔥' * (i == 5 ? 1 : i) &&
                      w.style?.fontSize != null,
                ),
              )
              .last,
        );
        expect(text.style?.fontSize, [56, 44, 34, 17, 56][i - 1]);
      }
    }
    await fixture.chat.react('alice_fred', 'emoji2', '❤️');
    await settleUi(t);
    expect(find.byKey(const ValueKey('reaction-emoji2-❤️')), findsOneWidget);
    await t.ensureVisible(bubble(2));
    await t.longPress(bubble(2));
    await t.pumpAndSettle();
    final select = find.byKey(const ValueKey('messageAction-select'));
    await t.ensureVisible(select);
    await t.tap(select);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('copySelectedMessages')), findsOneWidget);
    expect(find.byKey(const ValueKey('messageBubble-emoji2')), findsOneWidget);
  });
}

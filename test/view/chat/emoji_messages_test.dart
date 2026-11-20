import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/view/chat/widgets/message_bubble.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'timestamp pills use each sender’s chosen colour in ${brightness.name}',
      (t) async {
        final f = UiFixture();
        addTearDown(f.session.close);
        f.secrets.data[ChatAppearance.storageKey] = 'ocean';
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              ...f.overrides,
              knownPeerColorProvider('fred')
                  .overrideWithValue(ChatBubbleColor.plum),
            ],
            child: MaterialApp(
              theme: fireplaceTheme(brightness),
              home: Scaffold(
                body: Column(
                  children: [
                    MessageBubble(
                      message: message(id: 'mine', body: '🔥', outgoing: true),
                    ),
                    MessageBubble(
                      message: message(id: 'theirs', body: '🌷🌷'),
                    ),
                    MessageBubble(
                      message: message(id: 'group', body: '🍎🍎🍎'),
                      incomingColor: ChatBubbleColor.forest,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await settleUi(t);
        for (final (id, fill) in [
          ('mine', ChatBubbleColor.ocean.outgoing),
          ('theirs', ChatBubbleColor.plum.incoming(brightness)),
          ('group', ChatBubbleColor.forest.incoming(brightness)),
        ]) {
          final pill = t.widget<Container>(
            find.byKey(ValueKey('emojiTime-$id')),
          );
          expect((pill.decoration as BoxDecoration).color, fill);
        }
      },
    );
  }

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

  testWidgets('a space keeps the bubble; a focused bare emoji is outlined', (
    t,
  ) async {
    final fixture = UiFixture();
    await fixture.seed();
    addTearDown(fixture.session.close);
    for (final (id, body) in [('spaced', '🔥 '), ('bare', '🔥')]) {
      await fixture.chat.store.add(
        message(
          id: id,
          body: body,
          outgoing: true,
          at: fixtureTime.add(Duration(minutes: id == 'bare' ? 2 : 1)),
        ),
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
    final spaced = find.byKey(const ValueKey('messageBubble-spaced'));
    final bare = find.byKey(const ValueKey('messageBubble-bare'));
    expect(t.widget<Container>(spaced).decoration, isNotNull);
    expect(t.widget<Container>(bare).decoration, isNull);

    // Keyboard focus: the outline must show on the page, so it takes the
    // page's text colour, not the white of an outgoing bubble's text.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    Focus.of(t.element(bare)).requestFocus();
    await t.pump();
    final outline =
        t.widget<Container>(bare).foregroundDecoration! as BoxDecoration;
    final text = Theme.of(t.element(bare)).extension<FireplaceUiTokens>()!.text;
    expect((outline.border! as Border).top.color, text);
  });
}

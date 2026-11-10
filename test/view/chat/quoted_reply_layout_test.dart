import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/widgets/message_quote_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

const phone = Size(375, 812);

Finder bubble(String id) => find.byKey(ValueKey('messageBubble-$id'));
Finder quote(String id) => find.byKey(ValueKey('messageQuote-$id'));

LocalMessage reply(
  String id,
  String body,
  String quoted, {
  bool outgoing = true,
  String from = 'fred',
  int minutes = 1,
}) => LocalMessage(
  id: id,
  chatId: 'alice_fred',
  senderUid: outgoing ? 'alice' : 'fred',
  senderDevice: 'example-device',
  outgoing: outgoing,
  sentAt: fixtureTime.add(Duration(minutes: minutes)),
  body: body,
  status: MessageStatus.ok,
  quote: MessageQuote(targetId: '5', senderUid: from, body: quoted),
);

Future<void> openChat(
  WidgetTester t,
  UiFixture f, {
  Brightness brightness = Brightness.dark,
  double textScale = 1,
}) async {
  t.view.physicalSize = phone;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const ChatScreen(chatId: 'alice_fred'),
      ),
    ),
  );
  await settleUi(t);
}

void main() {
  testWidgets('a short reply to a short message stays a small bubble', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await f.chat.store.add(reply('short', 'ok', 'hi', from: 'alice'));
    await openChat(t, f);
    final box = t.getRect(bubble('short'));
    final panel = t.getRect(quote('short'));
    // Far narrower than the widest a bubble may be (80% of the row).
    expect(box.width, lessThan(phone.width * .45));
    expect(box.right, phone.width - 16);
    // The panel sits eight points inside the bubble and spans it.
    expect(panel.left - box.left, 8);
    expect(box.right - panel.right, 8);
    expect(panel.top - box.top, moreOrLessEquals(8, epsilon: 4.01));
  });

  testWidgets('the bubble grows with a longer reply and stretches the quote', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await f.chat.store.add(reply('short', 'ok', 'hi', minutes: 1));
    await f.chat.store.add(
      reply(
        'wide',
        'A noticeably longer reply than its quote',
        'hi',
        minutes: 2,
      ),
    );
    await openChat(t, f);
    final small = t.getRect(bubble('short'));
    final wide = t.getRect(bubble('wide'));
    expect(wide.width, greaterThan(small.width + 60));
    final panel = t.getRect(quote('wide'));
    expect(panel.left - wide.left, 8);
    expect(wide.right - panel.right, 8);
  });

  testWidgets('the bubble grows with a longer quote, up to the usual limit', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await f.chat.store.add(
      reply('quoted', 'ok', 'A quoted message that is fairly long', minutes: 1),
    );
    await f.chat.store.add(
      reply(
        'huge',
        'ok',
        List.filled(30, 'A very long quoted message.').join(' '),
        minutes: 2,
      ),
    );
    await openChat(t, f);
    final limit = (phone.width - 32) * .8;
    final quoted = t.getRect(bubble('quoted'));
    expect(quoted.width, greaterThan(150));
    expect(quoted.width, lessThanOrEqualTo(limit + .01));
    final huge = t.getRect(bubble('huge'));
    expect(huge.width, moreOrLessEquals(limit, epsilon: .01));
    // Two lines of the original at most, however long it was.
    final text = t.widget<Text>(
      find.descendant(of: quote('huge'), matching: find.byType(Text)).last,
    );
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(t.takeException(), isNull);
  });

  testWidgets('a received reply hugs its content on the left', (t) async {
    final f = UiFixture();
    await f.seed();
    await f.chat.store.add(
      reply('in', 'Lovely', 'See you there', outgoing: false, from: 'alice'),
    );
    await openChat(t, f);
    final box = t.getRect(bubble('in'));
    expect(box.left, 16);
    // Narrower than the widest a bubble may be.
    expect(box.width, lessThan((phone.width - 32) * .8 - 20));
    expect(
      find.descendant(of: quote('in'), matching: find.text('You')),
      findsOneWidget,
    );
  });

  testWidgets('the panel has a four-point stripe and ten-point corners', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await f.chat.store.add(reply('mine', 'ok', 'hi'));
    await f.chat.store.add(
      reply('theirs', 'ok', 'hi', outgoing: false, from: 'alice', minutes: 2),
    );
    await openChat(t, f);
    for (final id in ['mine', 'theirs']) {
      final clip = t.widget<ClipRRect>(
        find.descendant(of: quote(id), matching: find.byType(ClipRRect)),
      );
      expect(clip.borderRadius, BorderRadius.circular(10));
      final stripe = find
          .descendant(of: quote(id), matching: find.byType(SizedBox))
          .evaluate()
          .map((e) => e.widget as SizedBox)
          .where((box) => box.width == MessageQuotePreview.stripe);
      expect(stripe, hasLength(1));
    }
    Color ink(String id) => t
        .widget<Text>(
          find.descendant(of: quote(id), matching: find.byType(Text)).first,
        )
        .style!
        .color!;
    // Dark text on the pale wash of one's own bubble; the bubble's own text
    // colour on a received one.
    expect(ink('mine'), FireplaceUiTokens.light.text);
    expect(ink('theirs'), FireplaceUiTokens.dark.incomingText);
  });

  testWidgets('enlarged text keeps the reply inside the bubble limit', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await f.chat.store.add(
      reply(
        'big',
        'A longer reply than usual',
        'A quoted message of some length',
      ),
    );
    await openChat(t, f, textScale: 2);
    expect(t.takeException(), isNull);
    expect(
      t.getRect(bubble('big')).width,
      lessThanOrEqualTo((phone.width - 32) * .8 + .01),
    );
  });

  testWidgets('a message without a quote is unchanged', (t) async {
    final f = UiFixture();
    await f.seed();
    await openChat(t, f);
    final box = t.getRect(bubble('5'));
    final text = t.getRect(
      find.descendant(
        of: bubble('5'),
        matching: find.text(
          'Around two? There is no rush.',
          findRichText: true,
        ),
      ),
    );
    expect(text.left - box.left, 14);
  });
}

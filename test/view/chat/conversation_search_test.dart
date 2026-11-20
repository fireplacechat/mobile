// Issue 246: search inside one conversation, stepping through matches with
// up and down, the matching words marked in the bubbles.
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/conversation_search.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

final field = find.byKey(const Key('conversationSearchField'));
final count = find.byKey(const Key('conversationSearchCount'));
final older = find.byKey(const Key('conversationSearchOlder'));
final newer = find.byKey(const Key('conversationSearchNewer'));

String label(WidgetTester t) => t.widget<Text>(count).data!;

/// Every piece of text marked as a match in the conversation.
List<String> marked(WidgetTester t) => [
  for (final rich in t.widgetList<RichText>(find.byType(RichText)))
    ..._marks(rich.text),
];

Iterable<String> _marks(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  if (span.style?.backgroundColor != null && span.text != null) {
    yield span.text!;
  }
  for (final c in span.children ?? const <InlineSpan>[]) {
    yield* _marks(c);
  }
}

Future<UiFixture> openChat(WidgetTester t, {int extra = 0}) async {
  final f = UiFixture();
  await f.seed();
  addTearDown(f.session.close);
  for (var i = 0; i < extra; i++) {
    await f.chat.store.add(
      message(
        id: 'old$i',
        body: i == 0 ? 'The first lantern' : 'Filler $i',
        at: fixtureTime.subtract(Duration(days: 30, minutes: extra - i)),
      ),
    );
  }
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        home: const ChatScreen(chatId: 'alice_fred'),
      ),
    ),
  );
  await settleUi(t);
  return f;
}

/// Opens the search from the person's profile, as people will.
Future<void> openSearch(WidgetTester t) async {
  await t.tap(find.byKey(const Key('chatDetails')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('profileSearch')));
  await t.pumpAndSettle();
  expect(field, findsOneWidget);
}

Future<void> search(WidgetTester t, String text) async {
  await t.enterText(field, text);
  await t.pump(ConversationSearch.debounce);
  await settleUi(t);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('finds, counts and marks matches; Back closes the bar', (
    t,
  ) async {
    await openChat(t);
    await openSearch(t);
    await search(t, 'GARDEN');
    expect(label(t), '1 of 1');
    expect(marked(t), ['garden']);
    // Back closes the search, not the chat, and the marks go.
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(field, findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(marked(t), isEmpty);
  });

  testWidgets('no matches says so', (t) async {
    await openChat(t);
    await openSearch(t);
    await search(t, 'zebra');
    expect(label(t), 'No matches');
    expect(t.widget<IconButton>(older).onPressed, isNull);
    expect(t.widget<IconButton>(newer).onPressed, isNull);
  });

  testWidgets('steps older and newer, reaching beyond the loaded history', (
    t,
  ) async {
    // Older than the 200 messages a chat loads at first.
    await openChat(t, extra: 260);
    await openSearch(t);
    await search(t, 'e');
    expect(label(t), startsWith('1 of 100'));
    await search(t, 'lantern');
    expect(label(t), '1 of 1');
    // The match was found in the history and scrolled into view.
    expect(find.text('The first lantern', findRichText: true), findsWidgets);
    await search(t, 'filler 25');
    // "Filler 25" and "Filler 250" to "Filler 259": newest first.
    expect(label(t), '1 of 11');
    await t.tap(older);
    await settleUi(t);
    await t.pumpAndSettle();
    expect(label(t), '2 of 11');
    await t.tap(newer);
    await settleUi(t);
    await t.pumpAndSettle();
    expect(label(t), '1 of 11');
  });

  testWidgets('typing waits for a pause before searching', (t) async {
    var finds = 0;
    final s = ConversationSearch(
      find: (query, limit) async {
        finds++;
        return ['a', 'b'];
      },
      jump: (_) async {},
    );
    addTearDown(s.dispose);
    s.open();
    s.type('h');
    s.type('he');
    s.type('hel');
    await t.pump(const Duration(milliseconds: 200));
    expect(finds, 0);
    await t.pump(const Duration(milliseconds: 100));
    expect(finds, 1);
    expect(s.label, '1 of 2');
    s.close();
    expect(s.active, isFalse);
    expect(s.hits, isEmpty);
  });

  testWidgets('more than the limit shows as 100+', (t) async {
    final s = ConversationSearch(
      find: (query, limit) async => [for (var i = 0; i <= limit; i++) '$i'],
      jump: (_) async {},
    );
    addTearDown(s.dispose);
    s.type('x');
    await t.pump(ConversationSearch.debounce);
    expect(s.label, '1 of 100+');
    expect(s.hits, hasLength(100));
  });

  test('marking keeps the rest of the text, its style and its taps', () {
    final tap = TapGestureRecognizer();
    addTearDown(tap.dispose);
    const mark = TextStyle(backgroundColor: Color(0xFFFFFF00));
    final span = markMatches(
      TextSpan(
        text: 'Tea, TEA and tea',
        style: const TextStyle(fontSize: 17),
        recognizer: tap,
      ),
      'tea',
      mark,
    );
    final pieces = (span as TextSpan).children!.cast<TextSpan>();
    expect(pieces.map((p) => p.text).join(), 'Tea, TEA and tea');
    expect(
      [
        for (final p in pieces)
          if (p.style == mark) p.text,
      ],
      ['Tea', 'TEA', 'tea'],
    );
    expect(pieces.every((p) => p.recognizer == tap), isTrue);
    expect(span.style!.fontSize, 17);
    // Accents count, as in the history search.
    final plain = TextSpan(text: 'café');
    expect(markMatches(plain, 'cafe', mark), same(plain));
    expect(markMatches(plain, '', mark), same(plain));
  });
}

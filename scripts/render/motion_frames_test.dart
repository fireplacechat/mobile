// Frames of motion, for review as animations; not part of the byte-identical
// catalog. TZ=UTC; set RENDER_EMOJI_FONT for emoji.
//   flutter test scripts/render/motion_frames_test.dart
//   python scripts/render/frames_to_gif.py build/frames/<name>
// - search-jump, search-jump-dark: a chat opened from a search result
//   scrolls to the message, highlights it briefly, and scrolls on freely.
// - quote-jump, quote-jump-dark: tapping the other person's quote of one of
//   my messages scrolls up to my message and highlights it.
// - reaction-lift: an emoji under a resting finger waits a moment, then
//   lifts and grows a little.
// - highlight/: the jump highlight at its strongest, for several chat colours
//   in light and dark mode.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_route_observer.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart';

const _step = Duration(milliseconds: 40);

Future<void> _write(
  WidgetTester tester,
  GlobalKey boundary,
  String path,
) async {
  final renderer =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final png = await tester.runAsync(() async {
    final image = await renderer.toImage(pixelRatio: 2);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List();
    } finally {
      image.dispose();
    }
  });
  File('build/frames/$path')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!);
}

Future<void> _frame(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
  int index,
) => _write(tester, boundary, '$name/${index.toString().padLeft(3, '0')}.png');

class _FixedColors extends ChatAppearance {
  _FixedColors(this.colors);
  final ChatBubbleColors colors;
  @override
  ChatBubbleColors build() => colors;
}

Future<GlobalKey> _mount(
  WidgetTester tester,
  UiFixture fixture,
  Widget home, {
  Brightness brightness = Brightness.light,
  ChatBubbleColors colors = const ChatBubbleColors(),
}) async {
  tester.view.physicalSize = const Size(390, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final boundary = GlobalKey();
  final theme = fireplaceTheme(brightness);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...fixture.overrides,
        chatBubbleColorsProvider.overrideWith(() => _FixedColors(colors)),
      ],
      child: RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorObservers: [chatRouteObserver],
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(
              fontFamilyFallback: const ['PreviewEmoji'],
            ),
          ),
          home: home,
        ),
      ),
    ),
  );
  return boundary;
}

/// The seeded five messages, then 30 newer ones of both colours.
Future<UiFixture> _longChat() async {
  final fixture = UiFixture();
  await fixture.seed();
  addTearDown(fixture.session.close);
  for (var i = 0; i < 30; i++) {
    await fixture.chat.store.add(
      message(
        id: 'later-$i',
        body: 'Later message ${i + 1}',
        outgoing: i.isEven,
        at: fixtureTime.add(Duration(hours: 1, minutes: i)),
      ),
    );
  }
  return fixture;
}

/// Lets the history load (it is read off the test's fake clock).
Future<void> _load(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

Future<void> _searchJump(
  WidgetTester tester,
  String name,
  Brightness brightness,
) async {
  final boundary = await _mount(
    tester,
    await _longChat(),
    const ChatScreen(chatId: 'alice_fred', initialMessageId: '1'),
    brightness: brightness,
  );
  await _load(tester);
  var index = 0;
  // The jump scrolls, and the highlight fades in and out.
  for (
    var t = Duration.zero;
    t < const Duration(milliseconds: 2400);
    t += _step
  ) {
    await _frame(tester, boundary, name, index++);
    await tester.pump(_step);
  }
  // Then scroll down: nothing stops it at the result any more.
  final list = tester
      .widget<ListView>(find.byKey(const Key('messageTimeline')))
      .controller!;
  final start = list.offset;
  for (var i = 1; i <= 12; i++) {
    list.jumpTo(start * (1 - i / 12));
    await tester.pump(_step);
    await _frame(tester, boundary, name, index++);
  }
  expect(tester.takeException(), isNull);
}

Future<void> _quoteJump(
  WidgetTester tester,
  String name,
  Brightness brightness,
) async {
  final fixture = await _longChat();
  // fred replies to one of my messages from further up.
  await fixture.chat.store.add(
    message(
      id: 'fred-reply',
      body: 'Yes, that one works for me.',
      at: fixtureTime.add(const Duration(hours: 2)),
    ).copyWith(
      quote: const MessageQuote(
        targetId: 'later-10',
        senderUid: 'alice',
        body: 'Later message 11',
      ),
    ),
  );
  final boundary = await _mount(
    tester,
    fixture,
    const ChatScreen(chatId: 'alice_fred'),
    brightness: brightness,
  );
  await _load(tester);
  await tester.pumpAndSettle();
  var index = 0;
  for (var i = 0; i < 8; i++) {
    await _frame(tester, boundary, name, index++);
    await tester.pump(_step);
  }
  await tester.tap(find.byKey(const ValueKey('messageQuote-fred-reply')));
  for (
    var t = Duration.zero;
    t < const Duration(milliseconds: 2400);
    t += _step
  ) {
    await tester.pump(_step);
    await _frame(tester, boundary, name, index++);
  }
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('quote-jump', (tester) async {
    await _quoteJump(tester, 'quote-jump', Brightness.light);
  });

  testWidgets('quote-jump-dark', (tester) async {
    await _quoteJump(tester, 'quote-jump-dark', Brightness.dark);
  });

  testWidgets('search-jump', (tester) async {
    await _searchJump(tester, 'search-jump', Brightness.light);
  });

  testWidgets('search-jump-dark', (tester) async {
    await _searchJump(tester, 'search-jump-dark', Brightness.dark);
  });

  const pairs = {
    'ember-stone': ChatBubbleColors(),
    'forest-stone': ChatBubbleColors(outgoing: ChatBubbleColor.forest),
    'ocean-stone': ChatBubbleColors(outgoing: ChatBubbleColor.ocean),
  };
  for (final brightness in Brightness.values) {
    for (final pair in pairs.entries) {
      final name = '${brightness.name}-${pair.key}';
      testWidgets('highlight $name', (tester) async {
        final boundary = await _mount(
          tester,
          await _longChat(),
          // A message between bubbles of both colours.
          const ChatScreen(chatId: 'alice_fred', initialMessageId: '4'),
          brightness: brightness,
          colors: pair.value,
        );
        await _load(tester);
        // In frame-sized steps, so the scroll and the fade-in both run.
        for (var i = 0; i < 18; i++) {
          await tester.pump(_step);
        }
        await _write(tester, boundary, 'highlight/$name.png');
        await tester.pump(const Duration(seconds: 2));
      });
    }
  }

  testWidgets('reaction-lift', (tester) async {
    final fixture = UiFixture();
    await fixture.seed();
    addTearDown(fixture.session.close);
    final boundary = await _mount(
      tester,
      fixture,
      const ChatScreen(chatId: 'alice_fred'),
    );
    await settleUi(tester);
    await tester.longPress(find.byKey(const ValueKey('messageBubble-5')));
    await tester.pumpAndSettle();
    final heart = find.byKey(const ValueKey('messageAction-react-❤️'));
    final thumbs = find.byKey(const ValueKey('messageAction-react-👍'));
    var index = 0;
    for (var i = 0; i < 4; i++) {
      await _frame(tester, boundary, 'reaction-lift', index++);
      await tester.pump(_step);
    }
    // The finger lands on the heart and rests there.
    final finger = await tester.startGesture(tester.getCenter(heart));
    for (var i = 0; i < 12; i++) {
      await _frame(tester, boundary, 'reaction-lift', index++);
      await tester.pump(_step);
    }
    // It slides to the thumbs up and rests again.
    await finger.moveTo(tester.getCenter(thumbs));
    for (var i = 0; i < 12; i++) {
      await _frame(tester, boundary, 'reaction-lift', index++);
      await tester.pump(_step);
    }
    await finger.cancel();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

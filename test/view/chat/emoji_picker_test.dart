import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/emoji_picker.dart';
import 'package:fireplace/src/view/chat/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

const phone = Size(375, 812);
const safeArea = EdgeInsets.only(top: 44, bottom: 34);

Finder bubble(String id) => find.byKey(ValueKey('messageBubble-$id'));
Finder action(String id) => find.byKey(ValueKey('messageAction-$id'));
Finder pick(String emoji) => find.byKey(ValueKey('pickReaction-$emoji'));
final sheet = find.byKey(const Key('emojiPicker'));
final search = find.byKey(const Key('emojiSearch'));
final lifted = find.byWidgetPredicate((w) => w is MessageBubble && w.preview);

Future<void> openChat(
  WidgetTester t,
  UiFixture f, {
  double keyboard = 0,
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
        theme: fireplaceTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: safeArea,
            viewPadding: safeArea,
            viewInsets: EdgeInsets.only(bottom: keyboard),
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const ChatScreen(chatId: 'alice_fred'),
      ),
    ),
  );
  await settleUi(t);
}

Future<void> openPicker(WidgetTester t, {String id = '5'}) async {
  await t.longPress(bubble(id));
  await t.pumpAndSettle();
  await t.tap(action('moreReactions'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the picker replaces the bar and list and keeps the message', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await openChat(t, f);
    await openPicker(t);

    final rect = t.getRect(sheet);
    expect(rect.top, closeTo(phone.height * (1 - .541), .5));
    expect(rect.bottom, phone.height);
    expect(rect.width, phone.width);
    // The held message stays readable above the sheet.
    expect(t.getRect(lifted).bottom, lessThanOrEqualTo(rect.top - 12 + .01));
    // The bar and list have faded out and no longer take taps.
    expect(action('reply').hitTestable(), findsNothing);
    expect(action('react-👍').hitTestable(), findsNothing);
    // Handle, search field and first grid row sit at the measured offsets.
    final handle = t.getRect(find.byKey(const Key('emojiPickerHandle')));
    expect(handle.size, const Size(36, 5));
    expect(handle.top - rect.top, 5);
    final field = t.getRect(search);
    expect(field.top - rect.top, 32);
    expect(field.left, 16);
    expect(field.right, phone.width - 16);
    expect(field.height, closeTo(47, .5));
    final first = t.getRect(pick('😀'));
    final second = t.getRect(pick('😃'));
    final below = t.getRect(pick('😂'));
    expect(first.size, const Size.square(38));
    expect(first.left, 16);
    expect(second.left - first.left, closeTo(50.83, .01));
    expect(below.top - first.top, 48);
    expect(below.left, first.left, reason: 'seven emoji in a row');
    expect(find.text('Smileys & People'), findsOneWidget);
  });

  testWidgets('choosing an emoji sends that reaction and closes everything', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await openChat(t, f);
    await openPicker(t);
    await t.tap(pick('🥰'));
    await t.pumpAndSettle();
    expect(f.chat.reactions, [('5', '🥰')]);
    expect(sheet, findsNothing);
    expect(lifted, findsNothing);
  });

  testWidgets('search filters locally by name and keyword', (t) async {
    final f = UiFixture();
    await f.seed();
    // Any platform call other than text input would be a lookup elsewhere.
    final calls = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await openChat(t, f);
    await openPicker(t);
    calls.clear();

    await t.enterText(search, 'red heart');
    await t.pumpAndSettle();
    expect(pick('❤️'), findsOneWidget);
    expect(pick('😀'), findsNothing);
    expect(find.text('Smileys & People'), findsNothing);
    expect(find.byKey(const Key('emojiCategories')), findsNothing);
    // First result, first cell.
    expect(t.getRect(pick('❤️')).left, 16);

    await t.enterText(search, 'hundred');
    await t.pumpAndSettle();
    expect(pick('💯'), findsOneWidget);

    await t.enterText(search, 'zzzzqqqq');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('emojiSearchEmpty')), findsOneWidget);

    await t.enterText(search, '');
    await t.pumpAndSettle();
    expect(pick('😀'), findsOneWidget);
    expect(find.byKey(const Key('emojiCategories')), findsOneWidget);
    expect(calls.where((m) => !m.startsWith('SystemSound')), isEmpty);

    await t.enterText(search, 'thumbs up');
    await t.pumpAndSettle();
    await t.tap(pick('👍'));
    await t.pumpAndSettle();
    expect(f.chat.reactions, [('5', '👍')]);
  });

  testWidgets('an emoji typed from the keyboard is offered as it is', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await openChat(t, f);
    await openPicker(t);
    // A family sequence is valid for reactions but not listed by search.
    await t.enterText(search, '🧑‍🚀');
    await t.pumpAndSettle();
    expect(pick('🧑‍🚀'), findsOneWidget);
    await t.tap(pick('🧑‍🚀').first);
    await t.pumpAndSettle();
    expect(f.chat.reactions, [('5', '🧑‍🚀')]);
  });

  testWidgets('searching opens the sheet to full height', (t) async {
    final f = UiFixture();
    await f.seed();
    await openChat(t, f);
    await openPicker(t);
    final resting = t.getRect(sheet).top;
    await t.tap(search);
    await t.pumpAndSettle();
    expect(t.getRect(sheet).top, lessThan(resting));
    expect(t.getRect(sheet).top, closeTo(safeArea.top + 10, .5));
  });

  testWidgets('category buttons jump to their section and follow scrolling', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await openChat(t, f);
    await openPicker(t);
    Finder category(String name) => find.byKey(ValueKey('emojiCategory-$name'));
    bool selected(String name) =>
        t.widget<IconButton>(category(name)).isSelected!;
    expect(selected('Smileys & People'), isTrue);
    // Category targets are 48 points across, with four points between them.
    expect(t.getSize(category('Smileys & People')), const Size.square(48));
    expect(
      t.getRect(category('Animals & Nature')).left -
          t.getRect(category('Smileys & People')).left,
      52,
    );
    await t.tap(category('Food & Drink'));
    await t.pumpAndSettle();
    expect(find.text('Food & Drink'), findsOneWidget);
    expect(pick('🍇'), findsOneWidget);
    expect(selected('Food & Drink'), isTrue);
    expect(selected('Smileys & People'), isFalse);
    await t.tap(category('Smileys & People'));
    await t.pumpAndSettle();
    expect(pick('😀'), findsOneWidget);
  });

  testWidgets('recent reactions come from this conversation, newest first', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await f.chat.react('alice_fred', '1', '💯');
    await f.chat.react('alice_fred', '3', '🔥');
    await openChat(t, f);
    await openPicker(t);
    expect(find.text('Recents'), findsOneWidget);
    final fire = find.byKey(const ValueKey('recentReaction-🔥'));
    final hundred = find.byKey(const ValueKey('recentReaction-💯'));
    expect(t.getRect(fire).left, 16);
    expect(t.getRect(hundred).left, greaterThan(t.getRect(fire).left));
    expect(find.byKey(const ValueKey('emojiCategory-Recents')), findsOneWidget);
    await t.tap(hundred);
    await t.pumpAndSettle();
    expect(f.chat.reactions.last, ('5', '💯'));
  });

  testWidgets('without earlier reactions there is no Recents section', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await openChat(t, f);
    await openPicker(t);
    expect(find.text('Recents'), findsNothing);
    expect(find.byKey(const ValueKey('emojiCategory-Recents')), findsNothing);
  });

  testWidgets('dragging the sheet down closes without reacting', (t) async {
    final f = UiFixture();
    await f.seed();
    await openChat(t, f);
    await openPicker(t);
    await t.drag(
      find.byKey(const Key('emojiPickerHandle')),
      const Offset(0, 500),
    );
    await t.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(lifted, findsNothing);
    expect(f.chat.reactions, isEmpty);
  });

  testWidgets('tapping outside or pressing Escape closes without reacting', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await openChat(t, f);
    await openPicker(t);
    await t.tapAt(const Offset(350, 60));
    await t.pumpAndSettle();
    expect(sheet, findsNothing);

    await openPicker(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(f.chat.reactions, isEmpty);
  });

  testWidgets('the sheet stays above the keyboard', (t) async {
    final f = UiFixture();
    await f.seed();
    await openChat(t, f, keyboard: 300);
    await openPicker(t);
    expect(t.getRect(sheet).bottom, phone.height - 300);
    expect(t.takeException(), isNull);
  });

  testWidgets('enlarged text keeps emoji inside their cells and labels names', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    final semantics = t.ensureSemantics();
    await openChat(t, f, textScale: 2);
    await openPicker(t);
    expect(t.takeException(), isNull);
    final cell = t.getSize(pick('😀'));
    final glyph = t.getSize(
      find.descendant(of: pick('😀'), matching: find.text('😀')),
    );
    expect(glyph.height, lessThanOrEqualTo(cell.height));
    expect(glyph.width, lessThanOrEqualTo(cell.width));
    expect(find.bySemanticsLabel('grinning face'), findsOneWidget);
    expect(t.getRect(search).height, greaterThan(47));
    semantics.dispose();
  });

  testWidgets('the picker lays out by itself with the measured metrics', (
    t,
  ) async {
    String? picked;
    var dismissed = false;
    t.view.physicalSize = phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        home: Scaffold(
          body: EmojiPickerSheet(
            recent: const ['🎉'],
            onPicked: (emoji) => picked = emoji,
            onDismissed: () => dismissed = true,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('recentReaction-🎉')));
    expect(picked, '🎉');
    expect(dismissed, isFalse);
    expect(EmojiPickerMetrics.cell, 38);
    expect(EmojiPickerMetrics.rowGap, 10);
  });
}

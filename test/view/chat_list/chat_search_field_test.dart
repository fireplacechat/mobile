import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

Future<void> pumpList(WidgetTester t, UiFixture f, {double scale = 1}) async {
  t.view.physicalSize = const Size(375, 812);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.dark, accent: ChatBubbleColor.ocean),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const ChatListScreen(),
      ),
    ),
  );
  await settleUi(t);
}

final search = find.byKey(const Key('chatSearch'));
TextField field(WidgetTester t) => t.widget<TextField>(search);

void main() {
  testWidgets('at rest it is a pill with a centred Search and no outline', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await pumpList(t, f);
    final box = t.getRect(search);
    expect(box.left, 16);
    expect(box.right, 375 - 16);
    expect(box.height, 48);
    final decoration = field(t).decoration!;
    for (final border in [decoration.border, decoration.enabledBorder]) {
      border as OutlineInputBorder;
      expect(border.borderSide, BorderSide.none);
      // Fully rounded ends.
      expect(border.borderRadius.topLeft.x, greaterThan(box.height / 2));
    }
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Search people and messages'), findsNothing);
    // The icon and the word are centred together.
    final icon = t.getRect(
      find.descendant(of: search, matching: find.byIcon(Icons.search)),
    );
    final word = t.getRect(find.text('Search'));
    expect(icon.right, lessThan(word.left));
    expect((icon.left + word.right) / 2, closeTo(box.center.dx, 1));
    expect(word.center.dy, closeTo(box.center.dy, 1));
  });

  testWidgets('typing shows a thin outline in the chosen color', (t) async {
    final f = UiFixture();
    await f.seed();
    await pumpList(t, f);
    final resting = t.getRect(search);
    await t.tap(search);
    await t.pumpAndSettle();
    expect(
      (field(t).decoration!.focusedBorder as OutlineInputBorder).borderSide,
      BorderSide(color: ChatBubbleColor.ocean.outgoing),
    );
    // Focused, the icon and the hint move to the start for typing.
    expect(t.getRect(search), resting);
    expect(
      t
          .getRect(
            find.descendant(of: search, matching: find.byIcon(Icons.search)),
          )
          .left,
      lessThan(40),
    );
    expect(t.getRect(find.text('Search')).left, lessThan(80));
    expect(find.byKey(const Key('clearChatSearch')), findsNothing);

    await t.enterText(search, 'fred');
    // The message search under the people shows progress; do not wait on it.
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('globalSearchResults')), findsOneWidget);
    expect(t.getRect(search), resting);
    await t.tap(find.byKey(const Key('clearChatSearch')));
    await settleUi(t);
    expect(field(t).controller!.text, isEmpty);
    expect(find.byKey(const Key('conversationList')), findsOneWidget);
    expect(find.byKey(const Key('clearChatSearch')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('enlarged text grows the pill instead of clipping', (t) async {
    final f = UiFixture();
    await f.seed();
    await pumpList(t, f, scale: 2);
    expect(t.getRect(search).height, greaterThan(48));
    expect(find.text('Search'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

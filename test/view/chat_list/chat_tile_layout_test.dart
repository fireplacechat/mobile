import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/chat_list/chat_list_stamp.dart';
import 'package:fireplace/src/view/chat_list/widgets/chat_tile.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

Future<void> pumpList(
  WidgetTester t,
  UiFixture f, {
  double textScale = 1,
}) async {
  t.view.physicalSize = const Size(375, 812);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const ChatListScreen(),
      ),
    ),
  );
  await settleUi(t);
}

Finder row(String chat) => find.byKey(ValueKey('conversation-$chat'));
Finder unread(String chat) => find.byKey(ValueKey('unread-$chat'));

void main() {
  testWidgets('a row uses the measured avatar, text and separator geometry', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await pumpList(t, f);
    final tile = t.getRect(row('alice_fred'));
    // 8 + 19.2 + 2 x 19.95 + 10 at the default text size.
    expect(tile.height, closeTo(77.1, .2));
    final avatar = t.getRect(
      find.descendant(
        of: row('alice_fred'),
        matching: find.byType(PersonAvatar),
      ),
    );
    expect(avatar.size, const Size.square(60));
    expect(avatar.left, 16);
    expect(avatar.center.dy, tile.center.dy);
    final name = t.getRect(
      find.descendant(of: row('alice_fred'), matching: find.text('fred')),
    );
    expect(name.left, 86);
    expect(name.top - tile.top, 8);
    // The date ends sixteen points from the edge.
    final date = t.getRect(
      find.descendant(of: row('alice_fred'), matching: find.text('12:00 pm')),
    );
    expect(date.right, 375 - 16);
    final divider = t.widget<Divider>(find.byType(Divider).first);
    expect(divider.indent, ChatTile.textInset);
    expect(divider.endIndent, ChatTile.edge);
    expect(divider.thickness, 1 / 3);
    // No menu button: the row is name, date, preview and count only.
    expect(
      find.descendant(
        of: row('alice_fred'),
        matching: find.byType(PopupMenuButton<String>),
      ),
      findsNothing,
    );
  });

  testWidgets('the avatar is an initial on brand orange, never a photo', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await pumpList(t, f);
    final avatar = find.descendant(
      of: row('alice_fred'),
      matching: find.byType(PersonAvatar),
    );
    final box = t.widget<Container>(
      find.descendant(of: avatar, matching: find.byType(Container)),
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.image, isNull);
    expect(
      (decoration.gradient! as LinearGradient).colors.last,
      FireplaceUiTokens.dark.accent,
    );
    final initial = t.widget<Text>(
      find.descendant(of: avatar, matching: find.text('F')),
    );
    expect(initial.style!.color, Colors.white);
    expect(initial.style!.fontWeight, FontWeight.w700);
    expect(initial.style!.fontSize, closeTo(26, .5));
    expect(
      find.descendant(of: avatar, matching: find.byType(Image)),
      findsNothing,
    );
    // Centred in the circle.
    expect(
      t.getCenter(find.descendant(of: avatar, matching: find.text('F'))),
      t.getCenter(avatar),
    );
  });

  test('initials come from the first and last word', () {
    expect(avatarInitials('dana'), 'D');
    expect(avatarInitials('  Robin   Vale '), 'RV');
    expect(avatarInitials('Ana Maria Lopez'), 'AL');
    expect(avatarInitials('marlow_echo'), 'M');
    expect(avatarInitials(''), '?');
  });

  testWidgets(
    'the count comes from local history and sits by the second line',
    (t) async {
      final f = UiFixture();
      await f.seed();
      await pumpList(t, f);
      // Three incoming messages in the local store have not been seen.
      expect(unread('alice_fred'), findsOneWidget);
      expect(
        find.descendant(of: unread('alice_fred'), matching: find.text('3')),
        findsOneWidget,
      );
      final tile = t.getRect(row('alice_fred'));
      final badge = t.getRect(unread('alice_fred'));
      // A circle for one digit (the test font's digits are extra wide).
      expect(badge.height, 20);
      expect(badge.width, closeTo(20, .5));
      expect(badge.right, 375 - 16);
      // Level with the middle of the second preview line.
      expect(badge.center.dy - tile.top, closeTo(8 + 19.2 + 19.95 * 1.5, .1));
      final fill =
          t
                  .widget<Container>(
                    find.descendant(
                      of: unread('alice_fred'),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as ShapeDecoration;
      expect(fill.color, FireplaceUiTokens.dark.accent);
      expect(unread('alice_bob'), findsNothing);

      // One more arrives in the local store: the count follows it.
      await f.chat.store.add(
        message(
          id: 'new',
          body: 'One more',
          at: fixtureTime.add(const Duration(minutes: 1)),
        ),
      );
      await settleUi(t);
      expect(
        find.descendant(of: unread('alice_fred'), matching: find.text('4')),
        findsOneWidget,
      );

      // Marking them seen on this device clears it; nothing came from a server.
      await f.session.chatPreferences.markSeen('alice_fred', [
        '1',
        '3',
        '5',
        'new',
      ]);
      await settleUi(t);
      expect(unread('alice_fred'), findsNothing);
    },
  );

  testWidgets('long counts become a pill and say their number aloud', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    for (var i = 0; i < 120; i++) {
      await f.chat.store.add(
        message(
          id: 'bulk-$i',
          body: 'Message $i',
          at: fixtureTime.add(Duration(seconds: i + 1)),
        ),
      );
    }
    final semantics = t.ensureSemantics();
    await pumpList(t, f);
    final badge = t.getRect(unread('alice_fred'));
    expect(badge.height, 20);
    expect(badge.width, greaterThan(20));
    expect(find.text('99+'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('123 unread messages')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('muting from a long press greys the count and marks the row', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await pumpList(t, f);
    await t.longPress(row('alice_fred'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mute chat'));
    await t.pumpAndSettle();
    await settleUi(t);
    expect(find.byKey(const ValueKey('muted-alice_fred')), findsOneWidget);
    final fill =
        t
                .widget<Container>(
                  find.descendant(
                    of: unread('alice_fred'),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as ShapeDecoration;
    expect(fill.color, FireplaceUiTokens.dark.separator);
    await t.longPress(row('alice_fred'));
    await t.pumpAndSettle();
    expect(find.text('Unmute chat'), findsOneWidget);
  });

  testWidgets('a screen reader can mute without the long press', (t) async {
    final f = UiFixture();
    await f.seed();
    final semantics = t.ensureSemantics();
    await pumpList(t, f);
    final node = t.getSemantics(row('alice_fred'));
    final data = node.getSemanticsData();
    final mute = data.customSemanticsActionIds!
        .map(CustomSemanticsAction.getAction)
        .singleWhere((action) => action!.label == 'Mute chat');
    t.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.customAction,
        nodeId: node.id,
        viewId: t.view.viewId,
        arguments: CustomSemanticsAction.getIdentifier(mute!),
      ),
    );
    await t.pumpAndSettle();
    await settleUi(t);
    expect(find.byKey(const ValueKey('muted-alice_fred')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the largest ordinary text size gives the reference row', (
    t,
  ) async {
    // The reference screenshot was taken at this setting: a 104 point row
    // with 21 and 20 point text. The sizes in code are the unscaled ones.
    final f = UiFixture();
    await f.seed();
    await pumpList(t, f, textScale: 1.35);
    expect(t.getRect(row('alice_fred')).height, closeTo(104, .5));
    final name = t.widget<Text>(
      find.descendant(of: row('alice_fred'), matching: find.text('fred')),
    );
    expect(name.style!.fontSize! * 1.35, closeTo(21, .7));
    expect(t.getRect(unread('alice_fred')).height, closeTo(27, .01));
    expect(t.takeException(), isNull);
  });

  testWidgets('enlarged text grows the row instead of overflowing', (t) async {
    final f = UiFixture();
    await f.seed();
    await pumpList(t, f, textScale: 2);
    expect(t.takeException(), isNull);
    expect(t.getRect(row('alice_fred')).height, greaterThan(150));
    expect(t.getRect(unread('alice_fred')).height, 40);
  });

  testWidgets('a conversation without messages keeps the row height', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    f.chat.summaries = [
      ...f.chat.summaries,
      ChatSummary('alice_nora', 'nora', fixtureTime),
    ];
    await pumpList(t, f);
    expect(t.getRect(row('alice_nora')).height, closeTo(77.1, .2));
    expect(
      find.descendant(
        of: row('alice_nora'),
        matching: find.text('Encrypted chat'),
      ),
      findsOneWidget,
    );
  });

  group('chatListStamp', () {
    const localizations = DefaultMaterialLocalizations();
    final now = DateTime(2026, 10, 4, 12);
    String stamp(DateTime at) => chatListStamp(at, now, localizations);
    test('shows a lower-case time today', () {
      expect(stamp(DateTime(2026, 10, 4, 9, 5)), '9:05 am');
      expect(stamp(DateTime(2026, 10, 4, 11, 30)), '11:30 am');
    });
    test('shows a weekday within the last week', () {
      expect(stamp(DateTime(2026, 10, 3, 23, 59)), 'Sat');
      expect(stamp(DateTime(2026, 9, 28, 0, 1)), 'Mon');
    });
    test('shows a date without the year after a week', () {
      expect(stamp(DateTime(2026, 9, 27, 18)), '09/27');
    });
    test('keeps the year when it differs', () {
      expect(stamp(DateTime(2025, 12, 31)), '12/31/2025');
    });
    test('treats a clock set back as today', () {
      expect(stamp(DateTime(2026, 10, 5, 8)), '8:00 am');
    });
  });
}

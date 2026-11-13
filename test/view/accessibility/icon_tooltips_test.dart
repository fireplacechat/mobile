import 'dart:async';

import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/auth/auth_screen.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_menu_parts.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/devices/devices_screen.dart';
import 'package:fireplace/src/view/notifications/in_app_notice.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

Future<UiFixture> mount(
  WidgetTester tester,
  Widget screen, {
  bool push = false,
  bool notices = false,
}) async {
  final fixture = UiFixture();
  await fixture.seed();
  addTearDown(fixture.session.close);
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: fixture.overrides,
      child: MaterialApp(
        navigatorKey: navigator,
        theme: fireplaceTheme(Brightness.light),
        builder: notices
            ? (_, child) =>
                  InAppNoticeHost(navigatorKey: navigator, child: child!)
            : null,
        home: push ? const Scaffold() : screen,
      ),
    ),
  );
  if (push) {
    navigator.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
  await settleUi(tester);
  await tester.pumpAndSettle();
  return fixture;
}

Future<void> holdIcon(WidgetTester tester, String name) async {
  final target = find.byTooltip(name);
  expect(target, findsOneWidget, reason: name);
  await tester.ensureVisible(target);
  await settleUi(tester);
  await tester.pump(const Duration(milliseconds: 200));
  final data = tester.getSemantics(target).getSemanticsData();
  expect('${data.label} ${data.tooltip}', contains(name));
  // The semantic button includes Flutter's transparent touch padding (the
  // send button's visible circle is deliberately smaller than its target).
  expect(data.rect.shortestSide, greaterThanOrEqualTo(48));
  // Some names also exist as visible menu text. A tooltip adds another
  // Text.rich instance; compare the count instead of banning that name.
  final text = find.text(name, findRichText: true);
  final before = text.evaluate().length;
  final gesture = await tester.startGesture(tester.getCenter(target));
  try {
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
    expect(
      text,
      findsNWidgets(before),
      reason: '$name must not show an overlay',
    );
  } finally {
    // A hold must not activate destructive actions while testing tooltips.
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 300));
  }
  final after = tester.getSemantics(target).getSemanticsData();
  expect('${after.label} ${after.tooltip}', contains(name));
}

void iconTest(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    }
  });
}

Future<void> openMessageMenu(WidgetTester tester) async {
  await tester.longPress(find.byKey(const ValueKey('messageBubble-5')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('messageActionsPanel')), findsOneWidget);
}

void main() {
  iconTest('password icons retain names without held labels', (tester) async {
    await mount(tester, const AuthScreen());
    await holdIcon(tester, 'Show password');
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    await holdIcon(tester, 'Hide password');
  });

  iconTest('Settings and Clear search have no held labels', (tester) async {
    await mount(tester, const ChatListScreen());
    await holdIcon(tester, 'Settings');
    await tester.enterText(find.byKey(const Key('chatSearch')), 'fred');
    await settleUi(tester);
    await holdIcon(tester, 'Clear search');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    // The chat-row hold menu remains available.
    await tester.longPress(
      find.byKey(const ValueKey('conversation-alice_fred')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mute chat'), findsOneWidget);
  });

  iconTest('Back, Verify and Send retain their accessible names', (
    tester,
  ) async {
    await mount(tester, const ChatScreen(chatId: 'alice_fred'));
    await tester.enterText(find.byKey(const Key('composer')), 'A draft');
    await holdIcon(tester, 'Back to chats');
    await holdIcon(tester, 'Verify security code');
    await holdIcon(tester, 'Send message');
  });

  iconTest('default Back and Remove device have no held labels', (
    tester,
  ) async {
    await mount(tester, const DevicesScreen(), push: true);
    await holdIcon(tester, 'Back');
    await holdIcon(tester, 'Remove device');
  });

  iconTest('select-text Close has no held label', (tester) async {
    await mount(tester, const ChatScreen(chatId: 'alice_fred'));
    unawaited(
      showSelectTextSheet(
        tester.element(find.byType(ChatScreen)),
        'A selectable message',
      ),
    );
    await tester.pumpAndSettle();
    await holdIcon(tester, 'Close');
  });

  iconTest('Cancel reply has no held label', (tester) async {
    await mount(tester, const ChatScreen(chatId: 'alice_fred'));
    await openMessageMenu(tester);
    await tester.tap(find.byKey(const ValueKey('messageAction-reply')));
    await tester.pumpAndSettle();
    await holdIcon(tester, 'Cancel reply');
  });

  iconTest('selection Delete and Forward have no held labels', (tester) async {
    await mount(tester, const ChatScreen(chatId: 'alice_fred'));
    await openMessageMenu(tester);
    await tester.tap(find.byKey(const ValueKey('messageAction-select')));
    await tester.pumpAndSettle();
    await holdIcon(tester, 'Delete');
    await holdIcon(tester, 'Forward');
  });

  iconTest('every quick reaction and More reactions has no held label', (
    tester,
  ) async {
    await mount(tester, const ChatScreen(chatId: 'alice_fred'));
    await openMessageMenu(tester);
    final names = tester
        .widgetList<ReactionBarButton>(find.byType(ReactionBarButton))
        .map((button) => button.reaction.label)
        .toList();
    expect(names.length, 7);
    expect(names, contains('More reactions'));
    for (final name in names) {
      await holdIcon(tester, name);
    }
    expect(find.byKey(const Key('messageActionsPanel')), findsOneWidget);
  });

  iconTest('every emoji category icon has no held label', (tester) async {
    await mount(tester, const ChatScreen(chatId: 'alice_fred'));
    await openMessageMenu(tester);
    await tester.tap(find.byTooltip('More reactions'));
    await tester.pumpAndSettle();
    for (final name in [
      'Smileys & People',
      'Animals & Nature',
      'Food & Drink',
      'Activities',
      'Travel & Places',
      'Objects',
      'Symbols',
      'Flags',
    ]) {
      await tester.scrollUntilVisible(
        find.byTooltip(name),
        100,
        scrollable: find.descendant(
          of: find.byKey(const Key('emojiCategories')),
          matching: find.byType(Scrollable),
        ),
      );
      await holdIcon(tester, name);
    }
  });

  iconTest('Dismiss notification has no held label', (tester) async {
    final fixture = await mount(tester, const ChatListScreen(), notices: true);
    await fixture.chat.store.add(
      message(id: 'arrives', body: 'A new note', at: fixtureTime),
    );
    await settleUi(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await holdIcon(tester, 'Dismiss notification');
  });
}

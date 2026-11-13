import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_selection.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'long_press_menu_test.dart' show action, bubble, openChat;

const copy = Key('copySelectedMessages');

MessageSelectionController selection(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ChatScreen)))
        .read(messageSelectionProvider('alice_fred').notifier);

MessageSelection selected(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ChatScreen)))
        .read(messageSelectionProvider('alice_fred'));

Future<void> mount(
  WidgetTester tester,
  UiFixture fixture,
  List<String> ids,
) async {
  await fixture.seed();
  addTearDown(fixture.session.close);
  await openChat(tester, fixture);
  for (final id in ids) {
    selection(tester).toggle(id);
  }
  await tester.pumpAndSettle();
}

List<String> recordClipboard(WidgetTester tester, {bool fail = false}) {
  final writes = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        if (fail) {
          throw PlatformException(code: 'failed', message: 'PRIVATE DETAIL');
        }
        writes.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return writes;
}

void main() {
  testWidgets(
    'Copy joins readable plain text in display order and keeps selection',
    (tester) async {
      final fixture = UiFixture();
      await fixture.chat.store.add(
        message(
          id: 'first',
          body: '**First** _line_',
          at: fixtureTime.add(const Duration(minutes: 1)),
        ),
      );
      await fixture.chat.store.add(
        message(
          id: 'second',
          body: 'Second ~~old~~ note',
          outgoing: true,
          at: fixtureTime.add(const Duration(minutes: 2)),
        ),
      );
      final writes = recordClipboard(tester);
      await mount(tester, fixture, ['second', 'first']);
      await tester.tap(find.byKey(copy));
      await tester.pumpAndSettle();
      expect(writes, ['First line\n\nSecond old note']);
      expect(find.text('Copied'), findsOneWidget);
      expect(selected(tester).ids, {'second', 'first'});
      expect(find.text('2 Selected'), findsOneWidget);
    },
  );

  testWidgets('Copy skips unreadable and remotely deleted selected messages', (
    tester,
  ) async {
    final fixture = UiFixture();
    await fixture.chat.store.add(
      message(
        id: 'unreadable',
        body: 'Unreadable fixture',
        status: MessageStatus.undecryptable,
      ),
    );
    await fixture.chat.store.add(
      message(
        id: 'deleted',
        body: 'Removed fixture',
      ).copyWith(remotelyDeleted: true),
    );
    final writes = recordClipboard(tester);
    await mount(tester, fixture, ['unreadable', 'deleted', '5']);
    await tester.tap(find.byKey(copy));
    await tester.pumpAndSettle();
    expect(writes, ['Around two? There is no rush.']);
    expect(selected(tester).ids, {'unreadable', 'deleted', '5'});
  });

  testWidgets(
    'an unreadable-only or empty selection does not write the clipboard',
    (tester) async {
      final fixture = UiFixture();
      await fixture.chat.store.add(
        message(
          id: 'unreadable',
          body: 'Unreadable fixture',
          status: MessageStatus.undecryptable,
        ),
      );
      final writes = recordClipboard(tester);
      await mount(tester, fixture, ['unreadable']);
      await tester.tap(find.byKey(copy));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      expect(find.text('Copied'), findsNothing);
      selection(tester).clear();
      await tester.pumpAndSettle();
      expect(find.byKey(copy), findsNothing);
      expect(writes, isEmpty);
    },
  );

  testWidgets(
    'clipboard failure gives the requested error and retains selection',
    (tester) async {
      recordClipboard(tester, fail: true);
      await mount(tester, UiFixture(), ['5']);
      await tester.tap(find.byKey(copy));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not copy these messages. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('PRIVATE DETAIL'), findsNothing);
      expect(selected(tester).ids, {'5'});
      final retryWrites = recordClipboard(tester);
      await tester.tap(find.byKey(copy));
      await tester.pumpAndSettle();
      expect(retryWrites, ['Around two? There is no rush.']);
      expect(find.text('Copied'), findsOneWidget);
    },
  );

  testWidgets('Copy uses the held-message copy icon', (tester) async {
    final fixture = UiFixture();
    await mount(tester, fixture, []);
    await tester.longPress(bubble('5'));
    await tester.pumpAndSettle();
    final heldIcon = tester
        .widget<Icon>(
          find.descendant(of: action('copy'), matching: find.byType(Icon)),
        )
        .icon;
    await tester.tap(action('select'));
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(find.byKey(copy));
    expect((button.icon as Icon).icon, heldIcon);
  });

  for (final (platform, size, scale) in [
    (TargetPlatform.android, const Size(360, 800), 1.0),
    (TargetPlatform.iOS, const Size(375, 812), 1.35),
    (TargetPlatform.android, const Size(320, 640), 2.0),
  ]) {
    testWidgets(
      'Copy is left of Forward with existing controls retained $platform $size $scale',
      (tester) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        try {
          await mount(tester, UiFixture(), ['5']);
          final copyRect = tester.getRect(find.byKey(copy));
          final forward = tester.getRect(
            find.byKey(const Key('forwardSelectedMessages')),
          );
          final delete = tester.getRect(
            find.byKey(const Key('deleteSelectedMessages')),
          );
          final count = tester.getRect(find.byKey(const Key('selectionCount')));
          expect(copyRect.right, forward.left);
          expect(copyRect.center.dy, forward.center.dy);
          expect(forward.right, size.width);
          expect(delete.left, 0);
          expect(count.center.dx, size.width / 2);
          for (final rect in [copyRect, forward, delete]) {
            expect(rect.shortestSide, greaterThanOrEqualTo(48));
          }
          expect(find.text('Delete All'), findsOneWidget);
          expect(find.text('Cancel'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      },
    );
  }
}

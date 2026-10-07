import 'dart:async';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

Future<void> pumpList(WidgetTester t, UiFixture f) async {
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        home: const ChatListScreen(),
      ),
    ),
  );
  await settleUi(t);
}

void main() {
  testWidgets(
    'search keeps requests separate and clear restores recency order',
    (t) async {
      final f = UiFixture();
      await f.seed();
      await pumpList(t, f);
      final fred = find.byKey(const ValueKey('conversation-alice_fred'));
      final bob = find.byKey(const ValueKey('conversation-alice_bob'));
      expect(t.getTopLeft(fred).dy, lessThan(t.getTopLeft(bob).dy));
      await t.enterText(find.byKey(const Key('chatSearch')), 'nobody');
      await t.pump();
      expect(find.byKey(const Key('requestsTile')), findsOneWidget);
      expect(find.text('No conversations found'), findsOneWidget);
      expect(find.textContaining('Around two?'), findsNothing);
      await t.tap(find.byKey(const Key('clearChatSearch')));
      await t.pump();
      expect(fred, findsOneWidget);
      expect(bob, findsOneWidget);
    },
  );
  testWidgets(
    'blocked, hidden and unresolved names do not leak into search results',
    (t) async {
      final f = UiFixture();
      await f.seed();
      f.blocked = {'bob'};
      f.hidden = {'alice_theo'};
      f.names['fred'] = Completer<String>().future;
      await pumpList(t, f);
      expect(
        find.byKey(const ValueKey('conversation-alice_bob')),
        findsNothing,
      );
      expect(find.byKey(const Key('requestsTile')), findsNothing);
      await t.enterText(find.byKey(const Key('chatSearch')), 'nobody');
      await t.pump();
      expect(
        find.byKey(const ValueKey('conversation-alice_fred')),
        findsNothing,
      );
      expect(find.text('Looking up usernames'), findsOneWidget);
    },
  );
  testWidgets('rapid conversation taps open one route and back restores list', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await pumpList(t, f);
    final tile = find.byKey(const ValueKey('conversation-alice_fred'));
    final callback = t.widget<ListTile>(tile).onTap!;
    callback();
    callback();
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    Navigator.of(t.element(find.byType(ChatScreen))).pop();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('chatSearch')), findsOneWidget);
  });
  testWidgets('start validates locally and suppresses duplicate operations', (
    t,
  ) async {
    final f = UiFixture();
    await pumpList(t, f);
    await t.tap(find.byKey(const Key('newChat')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('peerUsername')), 'a');
    await t.tap(find.byKey(const Key('startChat')));
    await t.pump();
    expect(f.chat.starts, isEmpty);
    expect(
      find.text('Use 3–20 letters, numbers or underscores.'),
      findsOneWidget,
    );
    f.chat.startHold = Completer<String>();
    await t.enterText(find.byKey(const Key('peerUsername')), 'fred');
    final submit = t
        .widget<TextField>(find.byKey(const Key('peerUsername')))
        .onSubmitted!;
    submit('fred');
    submit('fred');
    await t.pump();
    expect(f.chat.starts, ['fred']);
    expect(
      t.widget<TextField>(find.byKey(const Key('peerUsername'))).enabled,
      isFalse,
    );
    f.chat.startHold!.complete('alice_fred');
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
  });
  testWidgets('list retry recovers without showing internals', (t) async {
    final f = UiFixture();
    addTearDown(f.session.close);
    var tries = 0;
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...f.overrides,
          chatsProvider.overrideWith((ref) {
            tries++;
            return tries == 1
                ? Stream.error(StateError('private'))
                : Stream.value([]);
          }),
        ],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const ChatListScreen(),
        ),
      ),
    );
    await settleUi(t);
    expect(find.text('Could not load chats'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    await t.tap(find.text('Try again'));
    await settleUi(t);
    expect(find.text('Your conversations start here'), findsOneWidget);
    expect(tries, 2);
  });
  for (final brightness in Brightness.values) {
    testWidgets('narrow enlarged conversation list $brightness', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      f.names['fred'] = Future.value('very_long_username_here');
      await t.pumpWidget(
        ProviderScope(
          overrides: f.overrides,
          child: MaterialApp(
            theme: fireplaceTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const ChatListScreen(),
          ),
        ),
      );
      await settleUi(t);
      expect(t.takeException(), isNull);
    });
  }
}

import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/safety/requests_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import '../chat_list/swipe_back_test.dart' show dragRight;
import 'safety_ui_test.dart' show host, settle, world;

class _RefusedChat extends FixtureChat {
  @override
  Future<void> acceptRequest(String chatId) async =>
      throw StateError('offline');
}

void main() {
  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final (_, alice, bob) = await world(t);
    addTearDown(alice.close);
    addTearDown(bob.close);
    await t.runAsync(() => alice.chat.sendText('alice_bob', 'Hello'));
    await t.pumpWidget(host(bob, const ChatListScreen()));
    await settle(t);
    await t.tap(find.byKey(const Key('requestsTile')));
    await t.pumpAndSettle();
    await settle(t);
    expect(find.byType(RequestsScreen), findsOneWidget);
  }

  for (final banner in [false, true]) {
    testWidgets(
      'accept from ${banner ? 'banner' : 'requests'} returns to chat list',
      (t) async {
        await open(t);
        if (banner) {
          await t.tap(find.text('wants to chat'));
          await t.pumpAndSettle();
          await settle(t);
        }
        await t.tap(
          find.byKey(Key(banner ? 'acceptRequest' : 'accept_alice_bob')),
        );
        await settle(t);
        await t.pumpAndSettle();
        expect(find.byType(ChatScreen), findsOneWidget);
        expect(find.byKey(const Key('composer')), findsOneWidget);
        if (banner &&
            Theme.of(t.element(find.byType(ChatScreen))).platform ==
                TargetPlatform.android) {
          final gesture = await dragRight(t, 260);
          await gesture.up();
        } else {
          await t.tap(find.byKey(const Key('chatBack')));
        }
        await t.pumpAndSettle();
        expect(find.byType(ChatListScreen), findsOneWidget);
        expect(find.byType(RequestsScreen), findsNothing);
      },
      variant: TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  for (final action in ['ignore', 'block']) {
    testWidgets('$action leaves empty Requests open until Back', (t) async {
      await open(t);
      await t.tap(find.byKey(Key('${action}_alice_bob')));
      if (action == 'block') {
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        final confirm = find.byKey(const Key('confirmBlock'));
        await t.ensureVisible(confirm);
        await t.tap(confirm);
      }
      await settle(t);
      await t.pumpAndSettle();
      expect(find.text('No message requests'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(ChatListScreen), findsOneWidget);
    });
  }

  testWidgets('a failed acceptance keeps the request and its retry action', (
    t,
  ) async {
    final fixture = UiFixture(chat: _RefusedChat());
    await fixture.seed();
    addTearDown(fixture.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: fixture.overrides,
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const ChatListScreen(),
        ),
      ),
    );
    await settleUi(t);
    await t.tap(find.byKey(const Key('requestsTile')));
    await t.pumpAndSettle();
    final accept = find.byKey(const Key('accept_alice_theo'));
    await t.tap(accept);
    await t.pumpAndSettle();
    expect(
      find.text('Could not update this request. Try again.'),
      findsOneWidget,
    );
    expect(accept, findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(ChatListScreen), findsOneWidget);
  });
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/src/app.dart';
import 'package:fireplace/src/app/chat_list_warmup.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'alice';
}

Future<void> _launch(WidgetTester tester, UiFixture fixture) =>
    tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...fixture.overrides,
          authUserProvider.overrideWith((ref) => Stream.value(_User())),
        ],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const AuthGate(),
        ),
      ),
    );

void main() {
  testWidgets('the loading screen stays up until the first rows have names', (
    tester,
  ) async {
    final fixture = UiFixture(overrideAuth: false)..hasBackup = true;
    await fixture.seed();
    addTearDown(fixture.session.close);
    final fred = Completer<String>();
    fixture.names['fred'] = fred.future;
    await _launch(tester, fixture);
    await settleUi(tester);
    expect(find.byType(FireplaceSplash), findsOneWidget);
    expect(find.byType(ChatListScreen), findsNothing);

    fred.complete('fred');
    await settleUi(tester);
    expect(find.byType(FireplaceSplash), findsNothing);
    final row = find.byKey(const ValueKey('conversation-alice_fred'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('fred')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text('Around two? There is no rush.'),
      ),
      findsOneWidget,
    );
    expect(find.text('…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lookup that never answers does not hold the list back', (
    tester,
  ) async {
    final fixture = UiFixture(overrideAuth: false)..hasBackup = true;
    await fixture.seed();
    addTearDown(fixture.session.close);
    fixture.names['fred'] = Completer<String>().future;
    await _launch(tester, fixture);
    await settleUi(tester);
    expect(find.byType(ChatListScreen), findsNothing);

    await tester.pump(chatListWarmupLimit);
    await settleUi(tester);
    expect(find.byType(FireplaceSplash), findsNothing);
    expect(
      find.byKey(const ValueKey('conversation-alice_fred')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a message after launch does not bring the loading screen back', (
    tester,
  ) async {
    final fixture = UiFixture(overrideAuth: false)..hasBackup = true;
    await fixture.seed();
    addTearDown(fixture.session.close);
    await _launch(tester, fixture);
    await settleUi(tester);
    expect(find.byType(ChatListScreen), findsOneWidget);

    await tester.runAsync(
      () => fixture.chat.store.add(
        message(
          id: 'later',
          body: 'One more thing',
          at: fixtureTime.add(const Duration(minutes: 1)),
        ),
      ),
    );
    await settleUi(tester);
    expect(find.byType(FireplaceSplash), findsNothing);
    expect(find.text('One more thing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the first rows are the newest shown chats, capped', () {
    final at = DateTime(2026, 1, 1);
    final chats = [
      ChatSummary('alice_old', 'old', at),
      ChatSummary('alice_blocked', 'blocked', at.add(const Duration(days: 9))),
      ChatSummary('alice_hidden', 'hidden', at.add(const Duration(days: 9))),
      ChatSummary(
        'alice_stranger',
        'stranger',
        at.add(const Duration(days: 9)),
        initiator: 'stranger',
        accepted: false,
      ),
      ChatSummary(
        'alice_mine',
        'mine',
        at.add(const Duration(days: 8)),
        initiator: 'alice',
        accepted: false,
      ),
      ChatSummary('alice_new', 'new', at.add(const Duration(days: 1))),
      ChatSummary('alice_empty', 'empty', null),
    ];
    expect(
      [
        for (final c in firstChatRows(
          chats,
          'alice',
          {'blocked'},
          {'alice_hidden'},
        ))
          c.peerUid,
      ],
      ['mine', 'new', 'old', 'empty'],
    );
    final many = [
      for (var i = 0; i < 40; i++)
        ChatSummary('alice_p$i', 'p$i', at.add(Duration(minutes: i))),
    ];
    final first = firstChatRows(many, 'alice', const {}, const {});
    expect(first, hasLength(chatListWarmupRows));
    expect(first.first.peerUid, 'p39');
  });
}

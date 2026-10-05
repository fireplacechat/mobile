// REVIEW R01: with only a message request (no conversations) and NO search, the list must not claim
// "No conversations found / Try another username". Reproduced on feature/beta-ui-phases-1-5 @ b01a65d.
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/ui/chat_list_screen.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

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
  testWidgets('only a request, no search: no "No conversations found" claim', (
    t,
  ) async {
    final f = UiFixture();
    f.chat.summaries = [
      ChatSummary(
        'alice_theo',
        'theo',
        fixtureTime,
        initiator: 'theo',
        accepted: false,
      ),
    ];
    await pumpList(t, f);
    expect(find.byKey(const Key('requestsTile')), findsOneWidget);
    expect(
      find.text('No conversations found'),
      findsNothing,
      reason: 'nobody searched for anything',
    );
    expect(find.textContaining('Try another username'), findsNothing);
  });

  testWidgets(
    'a search with no match still says so, and keeps showing the requests row',
    (t) async {
      final f = UiFixture();
      await f.seed();
      await pumpList(t, f);
      await t.enterText(find.byKey(const Key('chatSearch')), 'nobody');
      await t.pump();
      expect(find.text('No conversations found'), findsOneWidget);
      expect(find.byKey(const Key('requestsTile')), findsOneWidget);
    },
  );

  testWidgets('a user with nothing at all sees the first-use state', (t) async {
    final f = UiFixture();
    await pumpList(t, f);
    expect(find.text('Your conversations start here'), findsOneWidget);
    expect(find.text('No conversations found'), findsNothing);
  });
}

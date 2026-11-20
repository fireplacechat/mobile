// Issue 248: Message requests at the top of the chat list shows who is
// waiting as a small stack of faces, names them, and counts them.
import 'dart:async';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/groups/group_avatar.dart';
import 'package:fireplace/src/view/safety/message_requests_row.dart';
import 'package:fireplace/src/view/safety/requests_screen.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

final row = find.byType(MessageRequestsRow);

Future<void> pump(
  WidgetTester t, {
  int people = 1,
  List<GroupInvitation> invitations = const [],
}) async {
  final f = UiFixture();
  await f.seed();
  addTearDown(f.session.close);
  // The fixture already has theo waiting; add more, older ones.
  f.chat.summaries = [
    ...f.chat.summaries,
    for (var i = 1; i < people; i++)
      ChatSummary(
        'alice_p$i',
        'p$i',
        fixtureTime.subtract(Duration(hours: i)),
        initiator: 'p$i',
        accepted: false,
      ),
  ];
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...f.overrides,
        groupInvitationsProvider.overrideWith(
          (ref) => Stream.value(invitations),
        ),
      ],
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        home: const ChatListScreen(),
      ),
    ),
  );
  await settleUi(t);
}

int faces() => find
    .descendant(of: row, matching: find.byType(PersonAvatar))
    .evaluate()
    .length;

String summary(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('requestsSummary'))).data!;

String count(WidgetTester t) => t
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('requestsCount')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  testWidgets('one person: their face, their name, a count of one', (t) async {
    await pump(t);
    expect(faces(), 1);
    expect(summary(t), 'theo wants to chat');
    expect(count(t), '1');
    expect(find.byIcon(Icons.mark_email_unread_outlined), findsNothing);
  });

  testWidgets('two and three people overlap in a row', (t) async {
    await pump(t, people: 3);
    expect(faces(), 3);
    expect(find.byKey(const Key('requestsMore')), findsNothing);
    expect(summary(t), 'theo, p1 and p2');
    expect(count(t), '3');
  });

  testWidgets('past three, the last place counts the rest', (t) async {
    await pump(t, people: 5);
    expect(faces(), 2);
    expect(
      find.descendant(
        of: find.byKey(const Key('requestsMore')),
        matching: find.text('+3'),
      ),
      findsOneWidget,
    );
    expect(summary(t), 'theo, p1 and 3 others');
    expect(count(t), '5');
  });

  testWidgets('a group invitation shows as a group, named by who sent it', (
    t,
  ) async {
    await pump(
      t,
      invitations: [
        GroupInvitation(
          gid: 'g1',
          inviter: 'dana',
          at: fixtureTime.add(const Duration(minutes: 1)),
        ),
      ],
    );
    expect(
      find.descendant(of: row, matching: find.byType(GroupAvatar)),
      findsOneWidget,
    );
    expect(summary(t), 'dana and theo');
    expect(count(t), '2');
  });

  testWidgets('while a name is loading, a general line and no placeholder', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    f.names['theo'] = Completer<String>().future;
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
    expect(summary(t), 'People who want to chat with you');
    expect(find.text('…'), findsNothing);
  });

  testWidgets('the empty Requests page draws places for faces, no envelope', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    f.hidden = {'alice_theo'};
    await t.pumpWidget(
      ProviderScope(
        overrides: f.overrides,
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const RequestsScreen(),
        ),
      ),
    );
    await settleUi(t);
    expect(find.text('No message requests'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsNWidgets(3));
    expect(find.byIcon(Icons.mark_email_read_outlined), findsNothing);
  });
}

import 'dart:async';

import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/model/chat/outgoing_sends.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'chat_list_discovery_test.dart' show pumpList;

void main() {
  final fred = find.byKey(const ValueKey('conversation-alice_fred'));
  final bob = find.byKey(const ValueKey('conversation-alice_bob'));

  Future<void> send(WidgetTester t, String chatId, String body) async {
    ProviderScope.containerOf(t.element(find.byType(ChatListScreen)))
        .read(outgoingSendsProvider.notifier)
        .enqueue(chatId, body);
    await settleUi(t);
  }

  testWidgets('a message shows in the list, and moves its chat up, while it is '
      'still being sent', (t) async {
    final f = UiFixture();
    await f.seed();
    f.chat.sendHold = Completer<void>();
    f.now = fixtureTime.add(const Duration(minutes: 1)); // the send is newest
    await pumpList(t, f);
    expect(t.getTopLeft(fred).dy, lessThan(t.getTopLeft(bob).dy));

    await send(t, 'alice_bob', 'On my way');
    expect(
      find.descendant(of: bob, matching: find.text('You: On my way')),
      findsOneWidget,
    );
    expect(
      t.getTopLeft(bob).dy,
      lessThan(t.getTopLeft(fred).dy),
      reason: 'the chat with the newest message comes first',
    );
    f.chat.sendHold!.complete();
    await settleUi(t);
  });

  testWidgets('a send that failed says so in the list', (t) async {
    final f = UiFixture();
    await f.seed();
    f.chat.sendError = ChatException('Refused for this test.');
    await pumpList(t, f);
    await send(t, 'alice_bob', 'On my way');
    expect(
      find.descendant(
        of: bob,
        matching: find.text('You (not sent): On my way'),
      ),
      findsOneWidget,
    );
  });
}

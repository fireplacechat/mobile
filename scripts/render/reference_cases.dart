// States rendered at the size of the owner's reference screenshots (a
// 375 x 812 point phone at three pixels per point) so they can be overlaid.
// All names and messages here are fictional.
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'catalog_case.dart';

const referenceSize = Size(375, 812);
const referencePadding = EdgeInsets.only(top: 44, bottom: 34);

LocalMessage _incoming(String peer, String id, Duration age, String body) =>
    LocalMessage(
      id: id,
      chatId: 'alice_$peer',
      senderUid: peer,
      senderDevice: 'example-device',
      outgoing: false,
      sentAt: fixtureTime.subtract(age),
      body: body,
      status: MessageStatus.ok,
    );

/// Five rows shaped like the reference: two-line previews, one unread count,
/// a one-line preview and a conversation without messages.
void seedReferenceChats(UiFixture f) {
  const people = {
    'robin': 'Robin Vale',
    'tabitha': 'Tabitha Frost',
    'dana': 'Dana',
    'marlow': 'marlow_echo',
    'juniper': 'Juniper Hale',
  };
  const ages = {
    'robin': Duration(days: 1),
    'tabitha': Duration(days: 2),
    'dana': Duration(days: 3),
    'marlow': Duration(days: 14),
    'juniper': Duration(days: 15),
  };
  f.chat.summaries = [
    for (final peer in people.keys)
      ChatSummary('alice_$peer', peer, fixtureTime.subtract(ages[peer]!)),
  ];
  for (final entry in people.entries) {
    f.names[entry.key] = Future.value(entry.value);
  }
  for (final (peer, body) in [
    ('robin', 'Hope your evening feels relaxed and calm.'),
    (
      'tabitha',
      'Thought I would write and say something kind. What is your take on it?',
    ),
    ('dana', 'garden-plan-final.png'),
    ('juniper', 'Just a warm note from me. Are you free between tasks?'),
  ]) {
    f.chat.store.add(_incoming(peer, 'ref-$peer', ages[peer]!, body));
  }
}

/// Replies of different lengths: a short one stays small, a long one grows.
void seedReferenceReplies(UiFixture f) {
  LocalMessage reply(
    String id,
    int minutes,
    bool outgoing,
    String body,
    String quotedFrom,
    String quoted,
  ) => LocalMessage(
    id: id,
    chatId: 'alice_fred',
    senderUid: outgoing ? 'alice' : 'fred',
    senderDevice: 'example-device',
    outgoing: outgoing,
    sentAt: fixtureTime.add(Duration(minutes: minutes)),
    body: body,
    status: MessageStatus.ok,
    quote: MessageQuote(targetId: '5', senderUid: quotedFrom, body: quoted),
  );
  f.chat.store
    ..add(
      reply(
        'reply-long',
        1,
        true,
        'A picnic blanket, lemonade, maybe some shortbread',
        'fred',
        'What would you even suggest I bring then',
      ),
    )
    ..add(
      reply(
        'reply-in',
        2,
        false,
        'Lovely',
        'alice',
        'A picnic blanket, lemonade, maybe some shortbread',
      ),
    )
    ..add(reply('reply-short', 3, true, 'test', 'alice', 'test'));
}

final referenceCases = <CatalogCase>[
  CatalogCase(
    'reference-replies',
    const ChatScreen(chatId: 'alice_fred'),
    size: referenceSize,
    padding: referencePadding,
    pixelRatio: 3,
    prepare: seedReferenceReplies,
  ),
  CatalogCase(
    'reference-chat-list',
    const ChatListScreen(),
    size: referenceSize,
    padding: referencePadding,
    pixelRatio: 3,
    prepare: seedReferenceChats,
    act: (t, f) async {
      // Everything except the first conversation has been read.
      for (final peer in ['tabitha', 'dana', 'juniper']) {
        await f.session.chatPreferences.markSeen('alice_$peer', ['ref-$peer']);
      }
      await settleUi(t);
    },
  ),
  for (final mine in [false, true])
    CatalogCase(
      'reference-message-menu-${mine ? 'outgoing' : 'incoming'}',
      const ChatScreen(chatId: 'alice_fred'),
      size: referenceSize,
      padding: referencePadding,
      pixelRatio: 3,
      act: (t, f) async {
        await t.longPress(
          find.byKey(ValueKey('messageBubble-${mine ? '4' : '5'}')),
        );
        await t.pumpAndSettle();
      },
    ),
  for (final state in ['picker', 'picker-search'])
    CatalogCase(
      'reference-emoji-$state',
      const ChatScreen(chatId: 'alice_fred'),
      size: referenceSize,
      padding: referencePadding,
      pixelRatio: 3,
      act: (t, f) async {
        // An earlier reaction of one's own fills the Recents row.
        await f.chat.react('alice_fred', '3', '💯');
        await settleUi(t);
        await t.longPress(find.byKey(const ValueKey('messageBubble-5')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('messageAction-moreReactions')));
        await t.pumpAndSettle();
        if (state == 'picker') return;
        await t.enterText(find.byKey(const Key('emojiSearch')), 'heart');
        await t.pumpAndSettle();
      },
    ),
];

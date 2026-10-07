import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/model/search/message_search.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  test('search finds plain displayed text, literal punctuation and emoji', () {
    final history = {
      'alice_fred': [
        message(id: '1', body: '**Hello** _café_ 👨‍👩‍👧‍👦 [.*]'),
        message(id: '2', body: 'HELLO again'),
        message(
          id: '3',
          body: 'hello unavailable',
          status: MessageStatus.undecryptable,
        ),
      ],
    };
    expect(searchMessages(history, 'hello').length, 2);
    expect(searchMessages(history, 'HELLO').length, 2);
    expect(searchMessages(history, 'cafe'), isEmpty);
    expect(
      searchMessages(history, 'CAFÉ').single.text,
      'Hello café 👨‍👩‍👧‍👦 [.*]',
    );
    expect(searchMessages(history, '👨‍👩‍👧‍👦').length, 1);
    expect(searchMessages(history, '[.*]').length, 1);
    expect(searchMessages(history, '**'), isEmpty);
    expect(searchMessages(history, '   '), isEmpty);
  });
  test('case folding maps highlight indices back to original UTF-16', () {
    final text = '😀 İSTANBUL';
    final hit = searchMessages({
      'a': [message(id: '1', body: text)],
    }, 'stanbul').single;
    expect(hit.text.substring(hit.start, hit.end), 'STANBUL');
  });
  test('newest 100 matching messages, all chats, unconfirmed included', () {
    final messages = [
      for (var i = 0; i < 150; i++)
        message(
          id: '$i',
          body: 'needle $i',
          at: fixtureTime.add(Duration(minutes: i)),
        ),
    ];
    final hits = searchMessages({'a': messages}, 'needle');
    expect(hits.length, 100);
    expect(hits.first.message.id, '149');
    expect(hits.last.message.id, '50');
    expect(
      searchMessages({
        'a': [
          message(
            id: 'pending',
            body: 'needle',
            status: MessageStatus.unconfirmed,
          ),
        ],
      }, 'needle').length,
      1,
    );
  });
  test(
    'other unread excludes this chat and muted chats, cap is display only',
    () {
      const state = ChatActivityState(
        unread: {'a': 3, 'b': 150, 'c': 20},
        muted: {'c'},
      );
      expect(state.otherUnread('a'), 150);
      expect(unreadLabel(150), '99+');
      expect(unreadLabel(2), '2');
    },
  );
}
